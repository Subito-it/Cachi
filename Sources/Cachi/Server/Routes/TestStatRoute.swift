import Foundation
import os
import Vapor

struct TestStatRoute: Routable {
    let method = HTTPMethod.GET
    let path = "/v1/teststats"
    let description = #"Test execution statistics (pass MD5({test.targetName}-{test.suite}-{test.name}-{device.model}-{device.os}). Example: MD5('SomeUITestTarget-TestLogins-testHappyPath()-iPhone 8-13.0')"#

    func respond(to req: Request) throws -> Response {
        os_log("Test stats request received", log: .default, type: .info)

        guard let md5Identifier = req.url.query else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Test stats for test with md5 id '%@' fetched in %fms", log: .default, type: .info, md5Identifier, benchmarkStop(benchId)) }

        let stats = State.shared.testStats(md5Identifier: md5Identifier)

        if let bodyData = try? JSONEncoder().encode(stats) {
            return Response(body: Response.Body(data: bodyData))
        } else {
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}
