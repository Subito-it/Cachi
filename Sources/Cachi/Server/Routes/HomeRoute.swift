import Foundation
import os
import Vapor

struct HomeRoute: Routable {
    let method = HTTPMethod.GET
    let path = "/"
    let description = "Home"

    func respond(to req: Request) throws -> Response {
        os_log("Home request received", log: .default, type: .info)

        return try ResultsRouteHTML().respond(to: req)
    }
}
