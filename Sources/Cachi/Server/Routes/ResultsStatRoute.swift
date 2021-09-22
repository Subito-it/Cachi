import Foundation
import HTTPKit
import os

struct ResultsStatRoute: Routable {
    let path = "/v1/results_stat"
    let description = #"Test execution statistics on all tests (pass target, device_model (e.g. iPhone 8), device_os (e.g. 14.4) and type [flaky, slowest, fastest])"#
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Results stats request received", log: .default, type: .info)
        
        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let targetName = queryItems.first(where: { $0.name == "target" })?.value,
              let deviceModel = queryItems.first(where: { $0.name == "device_model" })?.value,
              let deviceOs = queryItems.first(where: { $0.name == "device_os" })?.value,
              let rawStatType = queryItems.first(where: { $0.name == "type" })?.value,
              let statType = ResultBundle.TestStatsType(rawValue: rawStatType) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not all required parameters provided. Expecting target, device_model, device_os, type"))
            
            return promise.succeed(res)
        }

        let benchId = benchmarkStart()
        defer { os_log("Results stats for fetched in %fms", log: .default, type: .info, benchmarkStop(benchId)) }
        
        let stats = State.shared.resultsTestStats(target: targetName, device: .init(model: deviceModel, os: deviceOs), type: statType)

        let res: HTTPResponse
        if let bodyData = try? JSONEncoder().encode(stats) {
            res = HTTPResponse(body: HTTPBody(data: bodyData))
        } else {
            res = HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }
        
        return promise.succeed(res)
    }
}
