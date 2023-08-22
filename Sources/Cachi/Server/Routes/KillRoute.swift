import Foundation
import os
import Vapor

struct KillRoute: Routable {
    let method = HTTPMethod.GET
    let path = "/v1/kill"
    let description = "Quit Cachi"

    func respond(to _: Request) throws -> Response {
        os_log("Kill request received", log: .default, type: .info)
        exit(0)
    }
}
