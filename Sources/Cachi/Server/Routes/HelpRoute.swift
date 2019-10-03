import Foundation
import HTTPKit
import os

struct HelpRoute: Routable {
    let path = "/v1/help"
    let description = "List available commands"
    
    private let futureRoutes: () -> [AnyRoutable]

    init(futureRoutes: @escaping () -> [AnyRoutable]) {
        self.futureRoutes = futureRoutes
    }
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Reset request received", log: .default, type: .info)
        
        let routes = futureRoutes()

        var result = [String: String]()
        for route in routes {
            guard route.path != path, route.path.count > 0 else { continue }
            result[route.path] = route.description
        }

        let res: HTTPResponse
        if let bodyData = try? JSONEncoder().encode(result) {
            res = HTTPResponse(body: HTTPBody(data: bodyData))
        } else {
            res = HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }

        return promise.succeed(res)
    }
}
