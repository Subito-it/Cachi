import Foundation
import HTTPKit
import os

struct TestRoute: Routable {
    let path = "/v1/test"
    let description = "Test details (pass summaryIdentifier)"
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Test stats request received", log: .default, type: .info)
        
        guard let testSummaryIdentifier = req.url.query else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
        
        let benchId = benchmarkStart()
        defer { os_log("Result bundle with id '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }
        
        let res: HTTPResponse
        if let summaries = State.shared.testActionSummaries(summaryIdentifier: testSummaryIdentifier),
           let bodyData = try? JSONEncoder().encode(summaries) {
            res = HTTPResponse(body: HTTPBody(data: bodyData))
        } else {
            res = HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }
        
        return promise.succeed(res)
    }
}
