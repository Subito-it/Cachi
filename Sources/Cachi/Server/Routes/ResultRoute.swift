import Foundation
import os
import Vapor

struct ResultRoute: Routable {
    let method = HTTPMethod.GET
    let path = "/v1/result"
    let description = "Detail of result. Pass identifier"

    func respond(to req: Request) throws -> Response {
        os_log("Result request received", log: .default, type: .info)

        guard let resultIdentifier = req.url.query else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Result bundle with id '%@' fetched in %fms", log: .default, type: .info, resultIdentifier, benchmarkStop(benchId)) }

        let result = State.shared.result(identifier: resultIdentifier)

        if let bodyData = try? JSONEncoder().encode(result) {
            return Response(body: Response.Body(data: bodyData))
        } else {
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}
