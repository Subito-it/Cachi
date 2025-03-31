import Foundation
import os
import Vapor

struct TestRoute: Routable {
    static let path = "/v1/test"

    let method = HTTPMethod.GET
    let description = "Test details. Pass summaryIdentifier"

    func respond(to req: Request) throws -> Response {
        os_log("Test stats request received", log: .default, type: .info)

        guard let testSummaryIdentifier = req.url.query else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Result bundle with id '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }

        if let summaries = State.shared.testActionActivitySummaries(summaryIdentifier: testSummaryIdentifier),
           let bodyData = try? JSONEncoder().encode(summaries) {
            return Response(body: Response.Body(data: bodyData))
        } else {
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}
