import Foundation
import HTTPKit

struct RequestRouter: HTTPServerDelegate {
    private let baseUrl: URL
    private let parseDepth: Int
    
    let routes: [Routable]
    let unhandledRoute = UnhandledRoute()
    
    init(baseUrl: URL, parseDepth: Int) {
        self.baseUrl = baseUrl
        self.parseDepth = parseDepth
        
        var routes = [Routable]()
        routes = [
            ResetRoute(baseUrl: baseUrl, depth: parseDepth),
            ParseRoute(baseUrl: baseUrl, depth: parseDepth),
            KillRoute(),
            VersionRoute(),
            HomeRoute(),
            TestStatRoute(),
            TestSessionLogsRouteHTML(),
            TestRoute(),
            ResultsRoute(baseUrl: baseUrl, depth: parseDepth),
            ResultsIdentifiersRoute(baseUrl: baseUrl, depth: parseDepth),
            ResultRoute(),
            HelpRoute(futureRoutes: { routes.map { AnyRoutable($0) } }),
            ResultsRouteHTML(),
            ResultRouteHTML(baseUrl: baseUrl, depth: parseDepth),
            TestRouteHTML(),
            AttachmentRoute(),
            ImageRoute(),
            CSSRoute(),
            ScriptRoute()
        ]
        
        self.routes = routes
    }
    
    func respond(to req: HTTPRequest, on channel: Channel) -> EventLoopFuture<HTTPResponse> {
        let promise = channel.eventLoop.makePromise(of: HTTPResponse.self)
        
        if let route = routes.first(where: { req.url.path == $0.path }) {
            route.respond(to: req, with: promise)
        } else {
            unhandledRoute.respond(to: req, with: promise)
        }

        return promise.futureResult
    }
}
