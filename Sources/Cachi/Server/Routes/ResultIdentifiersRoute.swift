import Foundation
import HTTPKit
import os

struct ResultsIdentifiersRoute: Routable {
    let path = "/v1/results_identifiers"
    let description = "Return results identifiers (even before parsing has completed)"
    
    private let baseUrl: URL
    private let depth: Int
    
    init(baseUrl: URL, depth: Int) {
        self.baseUrl = baseUrl
        self.depth = depth
    }
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Results identifiers request received", log: .default, type: .info)
        
        let partialResultBundles = State.shared.partialResultBundles(baseUrl: baseUrl, depth: depth)
        
        let res: HTTPResponse
        if let bodyData = try? JSONEncoder().encode(partialResultBundles) {
            res = HTTPResponse(body: HTTPBody(data: bodyData))
        } else {
            res = HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }

        return promise.succeed(res)
    }
}
