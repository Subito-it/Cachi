import Foundation
import os
import Vapor

struct ResultsRoute: Routable {
    static let path: String = "/v1/results"

    let method = HTTPMethod.GET
    let description: String = "List of results"

    private let baseUrl: URL
    private let depth: Int
    private let mergeResults: Bool

    init(baseUrl: URL, depth: Int, mergeResults: Bool) {
        self.baseUrl = baseUrl
        self.depth = depth
        self.mergeResults = mergeResults
    }

    func respond(to _: Request) throws -> Response {
        os_log("Results request received", log: .default, type: .info)

        let results = State.shared.resultBundles

        var resultInfos = [ResultInfo]()

        for result in results {
            let info = ResultInfo(target_name: result.tests.first?.targetName ?? "",
                                  identifier: result.identifier,
                                  url: "\(ResultRoute.path)?\(result.identifier)",
                                  coverage_url: result.codeCoveragePerFolderJsonUrl != nil ? "\(CoverageRoute.path)?id=\(result.identifier)" : nil,
                                  html_url: "\(ResultRouteHTML.path)?id=\(result.identifier)",
                                  start_time: result.userInfo?.startDate ?? result.testStartDate,
                                  end_time: result.userInfo?.endDate ?? result.testEndDate,
                                  test_start_time: result.testStartDate,
                                  test_end_time: result.testEndDate,
                                  success_count: result.testsPassed.count,
                                  failure_count: result.testsUniquelyFailed.count,
                                  failure_by_system_count: result.testsFailedBySystem.count,
                                  count: result.tests.count,
                                  has_crashes: result.testsCrashCount > 0,
                                  destinations: result.destinations,
                                  branch: result.userInfo?.branchName,
                                  commit_hash: result.userInfo?.commitHash,
                                  commit_message: result.userInfo?.commitMessage,
                                  metadata: result.userInfo?.metadata)

            resultInfos.append(info)
        }

        if let bodyData = try? JSONEncoder().encode(resultInfos) {
            return Response(body: Response.Body(data: bodyData))
        } else {
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}

private struct ResultInfo: Codable {
    let target_name: String
    let identifier: String
    let url: String
    let coverage_url: String?
    let html_url: String
    let start_time: Date
    let end_time: Date
    let test_start_time: Date
    let test_end_time: Date
    let success_count: Int
    let failure_count: Int
    let failure_by_system_count: Int
    let count: Int
    let has_crashes: Bool
    let destinations: String
    let branch: String?
    let commit_hash: String?
    let commit_message: String?
    let metadata: String?
}
