import Foundation
import HTTPKit
import os

struct TestStatRoute: Routable {
    let path = "/v1/teststats"
    let description = #"Test execution statistics (pass MD5({test.targetName}-{test.suite}-{test.name}-{device.model}-{device.os}). Example: MD5('SomeUITestTarget-TestLogins-testHappyPath()-iPhone 8-13.0')"#
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Test stats request received", log: .default, type: .info)
        
        guard let md5Identifier = req.url.query else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
        
        let benchId = benchmarkStart()
        defer { os_log("Test stats for test with md5 id '%@' fetched in %fms", log: .default, type: .info, md5Identifier, benchmarkStop(benchId)) }
        
        let stats = State.shared.testStats(md5Identifier: md5Identifier)

        let res: HTTPResponse
        if let bodyData = try? JSONEncoder().encode(stats) {
            res = HTTPResponse(body: HTTPBody(data: bodyData))
        } else {
            res = HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }
        
        return promise.succeed(res)
    }
}
