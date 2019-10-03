import Foundation
import HTTPKit
import os

struct VersionRoute: Routable {
    let path = "/v1/version"
    let description = "Cachi version"
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Version request received", log: .default, type: .info)
        
        let res = HTTPResponse(body: HTTPBody(string: "\(Cachi.version)"))
        return promise.succeed(res)
    }
}
