import Foundation
import HTTPKit
import os

struct KillRoute: Routable {
    let path = "/v1/kill"
    let description = "Quit Cachi"

    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Kill request received", log: .default, type: .info)
        exit(0)
    }
}
