import Foundation
import os
import Vapor

struct ResetRoute: Routable {
    let method = HTTPMethod.GET
    let path = "/v1/reset"
    let description = "Reset and reparse results"

    private let baseUrl: URL
    private let depth: Int
    private let mergeResults: Bool

    init(baseUrl: URL, depth: Int, mergeResults: Bool) {
        self.baseUrl = baseUrl
        self.depth = depth
        self.mergeResults = mergeResults
    }

    func respond(to _: Request) throws -> Response {
        os_log("Reset request received", log: .default, type: .info)

        State.shared.reset()

        switch State.shared.state {
        case let .parsing(progress):
            return Response(body: Response.Body(string: #"{ "status": "parsing \#(Int(progress * 100))% done" }"#))
        default:
            State.shared.parse(baseUrl: baseUrl, depth: depth, mergeResults: mergeResults)
            return Response(body: Response.Body(stringLiteral: #"{ "status": "ready" }"#))
        }
    }
}
