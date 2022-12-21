import Foundation
import HTTPKit
import os

struct ParseRoute: Routable {
    let path = "/v1/parse"
    let description = "Parse new results"
    
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
        os_log("Parsing request received", log: .default, type: .info)
        
        let res: HTTPResponse
        
        switch State.shared.state {
        case let .parsing(progress):
            res = HTTPResponse(body: HTTPBody(string: #"{ "status": "parsing \#(Int(progress * 100))% done" }"#))
        default:
            DispatchQueue.global(qos: .userInteractive).async {
                State.shared.parse(baseUrl: self.baseUrl, depth: self.depth, mergeResults: self.mergeResults, ignoreSystemFailures: self.ignoreSystemFailures)
            }
            res = HTTPResponse(body: HTTPBody(staticString: #"{ "status": "ready" }"#))
        }
        
        return promise.succeed(res)
    }
}
