import Foundation
import HTTPKit

struct RequestRouter: HTTPServerDelegate {
    private let baseUrl: URL
    private let parseDepth: Int
    private let mergeResults: Bool

    let routes: [Routable]
    let unhandledRoute = UnhandledRoute()

    init(baseUrl: URL, parseDepth: Int, mergeResults: Bool) {
        self.baseUrl = baseUrl
        self.parseDepth = parseDepth
        self.mergeResults = mergeResults

        var routes = [Routable]()
        routes = [
            ResetRoute(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            ParseRoute(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            KillRoute(),
            VersionRoute(),
            HomeRoute(),
            TestStatRoute(),
            TestStatRouteHTML(baseUrl: baseUrl, depth: parseDepth),
            TestSessionLogsRouteHTML(),
            TestRoute(),
            ResultsRoute(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            ResultsIdentifiersRoute(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            ResultRoute(),
            HelpRoute(futureRoutes: { routes.map { AnyRoutable($0) } }),
            ResultsRouteHTML(),
            ResultsStatRoute(),
            ResultsStatRouteHTML(),
            ResultRouteHTML(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            TestRouteHTML(),
            AttachmentRoute(),
            ImageRoute(),
            CSSRoute(),
            ScriptRoute(),
            CoverageRoute(),
            CoverageRouteHTML(),
            CoverageFileRouteHTML(),
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
