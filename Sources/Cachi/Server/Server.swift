import Foundation
import os
import Vapor

struct Server {
    private let port: Int
    private let hostname = "0.0.0.0"
    private let routes: [Routable]
    private let attachmentViewers: [String: AttachmentViewerConfiguration]

    init(port: Int, baseUrl: URL, parseDepth: Int, mergeResults: Bool, attachmentViewers: [AttachmentViewerConfiguration]) {
        self.port = port
        self.attachmentViewers = Dictionary(uniqueKeysWithValues: attachmentViewers.map { ($0.fileExtension, $0) })

        var routes: [Routable] = [
            AttachmentRoute(),
            AttachmentViewerRoute(attachmentViewers: self.attachmentViewers),
            AttachmentViewerScriptRoute(attachmentViewers: self.attachmentViewers),
            CoverageFileRouteHTML(),
            CoverageRoute(),
            CoverageRouteHTML(),
            CSSRoute(),
            HomeRoute(),
            ImageRoute(),
            KillRoute(),
            ParseRoute(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            ResetRoute(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            ResultRoute(),
            ResultRouteHTML(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            ResultsIdentifiersRoute(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            ResultsRoute(baseUrl: baseUrl, depth: parseDepth, mergeResults: mergeResults),
            ResultsRouteHTML(),
            ResultsStatRoute(),
            ResultsStatRouteHTML(),
            ScriptRoute(),
            TestRoute(),
            TestRouteHTML(attachmentViewers: self.attachmentViewers),
            TestSessionLogsRouteHTML(),
            TestStatRoute(),
            TestStatRouteHTML(baseUrl: baseUrl, depth: parseDepth),
            VersionRoute(),
            VideoCaptureRoute(),
            XcResultDownloadRoute()
        ]

        routes.append(HelpRoute(routes: routes))

        self.routes = routes
    }

    func listen() throws {
        var env = Environment(name: "cachi", arguments: ["env=prod"])
        try LoggingSystem.bootstrap(from: &env)

        let app = Application(env)
        defer { app.shutdown() }

        app.http.server.configuration.port = port
        app.http.server.configuration.hostname = hostname
        app.http.server.configuration.supportVersions = [.one]
        app.http.server.configuration.responseCompression = .enabled

        for route in routes {
            app.on(route.method, type(of: route).path.pathComponents, use: route.respond)
        }

        app.middleware.use(NotFoundMiddleware(), at: .beginning)

        try app.run()
    }
}
