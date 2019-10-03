import Foundation
import HTTPKit
import os

struct ParseRoute: Routable {
    let path = "/v1/parse"
    let description = "Parse new results"
    
    private let baseUrl: URL
    private let depth: Int
    
    init(baseUrl: URL, depth: Int) {
        self.baseUrl = baseUrl
        self.depth = depth
    }
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Parsing request received", log: .default, type: .info)
        
        let res: HTTPResponse
        
        switch State.shared.state {
        case let .parsing(progress):
            res = HTTPResponse(body: HTTPBody(string: #"{ "status": "parsing \#(Int(progress * 100))% done" }"#))
        default:
            DispatchQueue.global(qos: .userInteractive).async {
                State.shared.parse(baseUrl: self.baseUrl, depth: self.depth)
            }
            res = HTTPResponse(body: HTTPBody(staticString: #"{ "status": "ready" }"#))
        }
        
        return promise.succeed(res)
    }
}
