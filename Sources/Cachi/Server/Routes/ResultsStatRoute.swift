import Foundation
import os
import Vapor

struct ResultsStatRoute: Routable {
    let method = HTTPMethod.GET
    let path = "/v1/results_stat"
    let description = #"Test execution statistics on all tests (pass target, device_model (e.g. iPhone 8), device_os (e.g. 14.4) and type [flaky, slowest, fastest])"#

    func respond(to req: Request) throws -> Response {
        os_log("Results stats request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let targetName = queryItems.first(where: { $0.name == "target" })?.value,
              let deviceModel = queryItems.first(where: { $0.name == "device_model" })?.value,
              let deviceOs = queryItems.first(where: { $0.name == "device_os" })?.value,
              let rawStatType = queryItems.first(where: { $0.name == "type" })?.value,
              let statType = ResultBundle.TestStatsType(rawValue: rawStatType)
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not all required parameters provided. Expecting target, device_model, device_os, type. Optionally you can pass the window_size to specify numer of events per test"))
        }

        let rawWindowSize = queryItems.first(where: { $0.name == "window_size" })?.value ?? "" // optional parameter

        let benchId = benchmarkStart()
        defer { os_log("Results stats for fetched in %fms", log: .default, type: .info, benchmarkStop(benchId)) }

        let stats = State.shared.resultsTestStats(target: targetName, device: .init(model: deviceModel, os: deviceOs), type: statType, windowSize: Int(rawWindowSize))

        if let bodyData = try? JSONEncoder().encode(stats) {
            return Response(body: Response.Body(data: bodyData))
        } else {
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}
