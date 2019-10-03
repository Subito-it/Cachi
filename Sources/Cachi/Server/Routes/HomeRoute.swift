import Foundation
import HTTPKit
import os

struct HomeRoute: Routable {
    let path = "/"
    let description = "Home"
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Home request received", log: .default, type: .info)
        
        return ResultsRouteHTML().respond(to: req, with: promise)
    }
}
