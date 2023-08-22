import Foundation
import os
import Vapor

struct ResultsIdentifiersRoute: Routable {
    let method = HTTPMethod.GET
    let path = "/v1/results_identifiers"
    let description = "Return results identifiers (even before parsing has completed)"

    private let baseUrl: URL
    private let depth: Int
    private let mergeResults: Bool

    init(baseUrl: URL, depth: Int, mergeResults: Bool) {
        self.baseUrl = baseUrl
        self.depth = depth
        self.mergeResults = mergeResults
    }

    func respond(to _: Request) throws -> Response {
        os_log("Results identifiers request received", log: .default, type: .info)

        let pendingResultBundles = State.shared.pendingResultBundles(baseUrl: baseUrl, depth: depth, mergeResults: mergeResults)

        if let bodyData = try? JSONEncoder().encode(pendingResultBundles) {
            return Response(body: Response.Body(data: bodyData))
        }

        return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
    }
}
