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

        let results = State.shared.resultSummaries()

        var resultInfos = [ResultInfo]()

        for result in results {
            let info = ResultInfo(target_name: result.firstTargetName ?? "",
                                  identifier: result.identifier,
                                  url: "\(ResultRoute.path)?\(result.identifier)",
                                  coverage_url: result.hasCoverage ? "\(CoverageRoute.path)?id=\(result.identifier)" : nil,
                                  html_url: "\(ResultRouteHTML.path)?id=\(result.identifier)",
                                  start_time: result.startDate,
                                  end_time: result.endDate,
                                  test_start_time: result.testStartDate,
                                  test_end_time: result.testEndDate,
                                  success_count: result.passedCount,
                                  failure_count: result.uniquelyFailedCount,
                                  failure_by_system_count: result.failedBySystemCount,
                                  count: result.totalCount,
                                  has_crashes: result.crashCount > 0,
                                  destinations: result.destinations,
                                  branch: result.branchName,
                                  commit_hash: result.commitHash,
                                  commit_message: result.commitMessage,
                                  metadata: result.metadata)

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
