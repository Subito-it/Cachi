import Foundation
import os
import Vapor

struct TestStatRouteV2: Routable {
    static let path = "/v2/teststats"

    let method = HTTPMethod.GET
    let description = "Test execution statistics (pass id={test_summary_identifier})"

    func respond(to req: Request) throws -> Response {
        os_log("Test stats request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "id" })?.value
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Test stats for test with summaryIdentifier '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }

        guard let stats = State.shared.testStats(summaryIdentifier: testSummaryIdentifier) else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        if let bodyData = try? JSONEncoder().encode(stats) {
            return Response(body: Response.Body(data: bodyData))
        } else {
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}
