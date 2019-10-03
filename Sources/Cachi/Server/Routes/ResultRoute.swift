import Foundation
import HTTPKit
import os

struct ResultRoute: Routable {
    let path = "/v1/result"
    let description = "Detail of result (pass identifier)"

    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Result request received", log: .default, type: .info)
        
        guard let resultIdentifier = req.url.query else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
        
        let benchId = benchmarkStart()
        defer { os_log("Result bundle with id '%@' fetched in %fms", log: .default, type: .info, resultIdentifier, benchmarkStop(benchId)) }
        
        let result = State.shared.result(identifier: resultIdentifier)

        let res: HTTPResponse
        if let bodyData = try? JSONEncoder().encode(result) {
            res = HTTPResponse(body: HTTPBody(data: bodyData))
        } else {
            res = HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }
        
        return promise.succeed(res)
    }
}
