import Foundation
import HTTPKit
import os

struct ResetRoute: Routable {
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

    func respond(to _: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Reset request received", log: .default, type: .info)

        State.shared.reset()

        let res: HTTPResponse
        switch State.shared.state {
        case let .parsing(progress):
            res = HTTPResponse(body: HTTPBody(string: #"{ "status": "parsing \#(Int(progress * 100))% done" }"#))
        default:
            State.shared.parse(baseUrl: baseUrl, depth: depth, mergeResults: mergeResults)
            res = HTTPResponse(body: HTTPBody(staticString: #"{ "status": "ready" }"#))
        }

        return promise.succeed(res)
    }
}
