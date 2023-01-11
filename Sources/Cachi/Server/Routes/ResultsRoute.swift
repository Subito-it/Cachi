import Foundation
import HTTPKit
import os

struct ResultInfo: Codable {
    let target_name: String
    let identifier: String
    let url: String
    let html_url: String
    let start_time: Date
    let end_time: Date
    let test_start_time: Date
    let test_end_time: Date
    let success_count: Int
    let failure_count: Int
    let count: Int
    let has_crashes: Bool
    let destinations: String
    let branch: String?
    let commit_hash: String?
    let commit_message: String?
    let metadata: String?
}

struct ResultsRoute: Routable {
    let path: String = "/v1/results"
    let description: String = "List of results"
    
    private let baseUrl: URL
    private let depth: Int
    private let mergeResults: Bool
    
    init(baseUrl: URL, depth: Int, mergeResults: Bool) {
        self.baseUrl = baseUrl
        self.depth = depth
        self.mergeResults = mergeResults
    }
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Results request received", log: .default, type: .info)
        
        let results = State.shared.resultBundles
        
        var resultInfos = [ResultInfo]()

        for result in results {
            let info = ResultInfo(target_name: result.tests.first?.targetName ?? "",
                                  identifier: result.identifier,
                                  url: "\(ResultRoute().path)?\(result.identifier)",
                                  html_url: "\(ResultRouteHTML(baseUrl: baseUrl, depth: depth, mergeResults: mergeResults).path)?id=\(result.identifier)",
                                  start_time: result.userInfo?.startDate ?? result.testStartDate,
                                  end_time: result.userInfo?.endDate ?? result.testEndDate,
                                  test_start_time: result.testStartDate,
                                  test_end_time: result.testEndDate,
                                  success_count: result.testsPassed.count,
                                  failure_count: result.testsUniquelyFailed.count,
                                  count: result.tests.count,
                                  has_crashes: result.testsCrashCount > 0,
                                  destinations: result.destinations,
                                  branch: result.userInfo?.branchName,
                                  commit_hash: result.userInfo?.commitHash,
                                  commit_message: result.userInfo?.commitMessage,
                                  metadata: result.userInfo?.metadata)
            
            resultInfos.append(info)
        }
                
        let res: HTTPResponse
        if let bodyData = try? JSONEncoder().encode(resultInfos) {
            res = HTTPResponse(body: HTTPBody(data: bodyData))
        } else {
            res = HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }

        return promise.succeed(res)
    }
}
