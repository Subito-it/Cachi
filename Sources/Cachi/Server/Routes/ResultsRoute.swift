import Foundation
import HTTPKit
import os

struct ResultInfo: Codable {
    let identifier: String
    let url: String
    let htmlUrl: String
    let date: Date
    let success_count: Int
    let failure_count: Int
    let count: Int
    let has_crashes: Bool
    let destinations: String
    let branch: String
    let commit_hash: String
    let commit_message: String
}

struct ResultsRoute: Routable {
    let path: String = "/v1/results"
    let description: String = "List of results"
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Results request received", log: .default, type: .info)
        
        let results = State.shared.resultBundles
        
        var resultInfos = [ResultInfo]()
        for result in results {
            let info = ResultInfo(identifier: result.identifier,
                                  url: "\(ResultRoute().path)?\(result.identifier)",
                                  htmlUrl: "\(ResultRouteHTML().path)?id=\(result.identifier)",
                                  date: result.date,
                                  success_count: result.testsPassed.count,
                                  failure_count: result.testsUniquelyFailed.count,
                                  count: result.tests.count,
                                  has_crashes: result.testsCrashCount > 0,
                                  destinations: result.destinations,
                                  branch: result.userInfo?.branchName ?? "",
                                  commit_hash: result.userInfo?.commitHash ?? "",
                                  commit_message: result.userInfo?.commitMessage ?? "")
            
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
