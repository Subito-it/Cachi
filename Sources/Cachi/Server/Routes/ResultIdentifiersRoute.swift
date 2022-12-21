import Foundation
import HTTPKit
import os

struct ResultsIdentifiersRoute: Routable {
    let path = "/v1/results_identifiers"
    let description = "Return results identifiers (even before parsing has completed)"
    
    private let baseUrl: URL
    private let depth: Int
    private let mergeResults: Bool
    private let ignoreSystemFailures: Bool
    
    init(baseUrl: URL, depth: Int, mergeResults: Bool, ignoreSystemFailures: Bool) {
        self.baseUrl = baseUrl
        self.depth = depth
        self.mergeResults = mergeResults
        self.ignoreSystemFailures = ignoreSystemFailures
    }
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Results identifiers request received", log: .default, type: .info)
        
        let pendingResultBundles = State.shared.pendingResultBundles(baseUrl: baseUrl, depth: depth, mergeResults: mergeResults, ignoreSystemFailures: ignoreSystemFailures)
        
        let res: HTTPResponse
        if let bodyData = try? JSONEncoder().encode(pendingResultBundles) {
            res = HTTPResponse(body: HTTPBody(data: bodyData))
        } else {
            res = HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }

        return promise.succeed(res)
    }
}
