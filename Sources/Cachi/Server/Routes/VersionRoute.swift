import Foundation
import os
import Vapor

struct VersionRoute: Routable {
    static let path = "/v1/version"
    
    let method = HTTPMethod.GET
    let description = "Cachi version"

    func respond(to _: Request) throws -> Response {
        os_log("Version request received", log: .default, type: .info)

        return Response(body: Response.Body(string: "\(Cachi.version)"))
    }
}
