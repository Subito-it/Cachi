import Foundation
import HTTPKit
import os

struct UnhandledRoute: Routable {
    let path = ""
    let description = ""
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Unhandled request received", log: .default, type: .info)
        
        let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: #":-( nothing here"#))
        return promise.succeed(res)
    }
}
