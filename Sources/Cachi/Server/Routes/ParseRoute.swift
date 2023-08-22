import Foundation
import os
import Vapor

struct ParseRoute: Routable {
    let method = HTTPMethod.GET
    let path = "/v1/parse"
    let description = "Parse new results"

    private let baseUrl: URL
    private let depth: Int
    private let mergeResults: Bool

    init(baseUrl: URL, depth: Int, mergeResults: Bool) {
        self.baseUrl = baseUrl
        self.depth = depth
        self.mergeResults = mergeResults
    }

    func respond(to _: Request) throws -> Response {
        os_log("Parsing request received", log: .default, type: .info)

        switch State.shared.state {
        case let .parsing(progress):
            return Response(body: Response.Body(string: #"{ "status": "parsing \#(Int(progress * 100))% done" }"#))
        default:
            DispatchQueue.global(qos: .userInteractive).async {
                State.shared.parse(baseUrl: baseUrl, depth: depth, mergeResults: mergeResults)
            }
            return Response(body: Response.Body(stringLiteral: #"{ "status": "ready" }"#))
        }
    }
}
