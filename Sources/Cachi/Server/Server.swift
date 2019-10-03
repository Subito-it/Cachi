import Foundation
import HTTPKit
import os

struct Server {
    private let port: Int
    private let hostname = "0.0.0.0"
    
    private let responder: RequestRouter

    init(port: Int, baseUrl: URL, parseDepth: Int) {
        self.port = port
        self.responder = RequestRouter(baseUrl: baseUrl, parseDepth: parseDepth)
    }
    
    func listen() throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer { try? elg.syncShutdownGracefully() }

        let server = HTTPServer(
            configuration: .init(
                hostname: hostname,
                port: port,
                supportCompression: true,
                supportVersions: [.one]
            ),
            on: elg
        )

        try server.start(delegate: responder).wait()

        os_log("Server starting on http://%@:%ld", log: .default, type: .info, hostname, port)
        try server.onClose.wait()
    }
}
