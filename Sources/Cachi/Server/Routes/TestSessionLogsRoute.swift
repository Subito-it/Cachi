import Foundation
import os
import Vapor

struct TestSessionLogsRoute: Routable {
    static let path = "/v1/session_logs"

    let method = HTTPMethod.GET
    let description = "Test session logs. Pass `id` parameter with test summary identifier"

    func respond(to req: Request) throws -> Response {
        os_log("Test session logs request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "id" })?.value
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Test session logs with summaryIdentifier '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }

        guard let (test, _) = State.shared.testWithResultBundle(summaryIdentifier: testSummaryIdentifier),
              let diagnosticsIdentifier = test.diagnosticsIdentifier,
              let sessionLogs = State.shared.testSessionLogs(diagnosticsIdentifier: diagnosticsIdentifier)
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        guard let bodyData = try? JSONEncoder().encode(sessionLogs) else {
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }

        return Response(body: Response.Body(data: bodyData))
    }
}
