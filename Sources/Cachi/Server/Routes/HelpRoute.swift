import Foundation
import os
import Vapor

struct HelpRoute: Routable {
    static let path = "/v1/help"
    
    let method = HTTPMethod.GET
    let description = "List available commands"

    let routes: [Routable]

    init(routes: [Routable]) {
        self.routes = routes
    }

    func respond(to _: Request) throws -> Response {
        os_log("Reset request received", log: .default, type: .info)

        var result = [String: String]()
        for route in routes {
            let routePath = type(of: route).path
            guard routePath != Self.path, routePath.count > 0 else { continue }
            result[routePath] = route.description
        }

        if let bodyData = try? JSONEncoder().encode(result) {
            return Response(body: Response.Body(data: bodyData))
        } else {
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}
