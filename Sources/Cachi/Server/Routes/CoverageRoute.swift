import Foundation
import os
import Vapor
import ZippyJSON

struct CoverageRoute: Routable {
    static let path = "/coverage"
    
    let method = HTTPMethod.GET
    let description = "Coverage. Pass `id` parameter with result identifier, `kind` [files/paths] (Default: files), `q` query string to filter results paths"

    func respond(to req: Request) throws -> Response {
        os_log("Coverage request received", log: .default, type: .info)

        let resultBundles = State.shared.resultBundles

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let resultBundle = resultBundles.first(where: { $0.identifier == resultIdentifier }),
              var pathCoverages = pathCoveragesForResult(resultBundle, for: Kind(queryItems: queryItems))
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        if let queryString = queryItems.first(where: { $0.name == "q" })?.value {
            pathCoverages = pathCoverages.filter { $0.path.contains(queryString) }
        }

        if let bodyData = resultData(pathCoverages, resultIdentifier: resultIdentifier, for: Kind(queryItems: queryItems)) {
            return Response(body: Response.Body(data: bodyData))
        }

        return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
    }

    private func pathCoveragesForResult(_ result: ResultBundle, for kind: Kind?) -> [PathCoverage]? {
        let kind = kind ?? .files

        guard let url = kind == .files ? result.codeCoverageJsonSummaryUrl : result.codeCoveragePerFolderJsonUrl,
              let coverageData = try? Data(contentsOf: url)
        else {
            return nil
        }

        switch kind {
        case .files:
            let result = try? ZippyJSONDecoder().decode(Coverage.self, from: coverageData)
            return result?.data.first?.files.map { PathCoverage(path: $0.filename, percent: $0.summary.lines.percent) }
        case .paths:
            return try? ZippyJSONDecoder().decode([PathCoverage].self, from: coverageData)
        }
    }

    private func resultData(_ pathCoverages: [PathCoverage], resultIdentifier: String, for kind: Kind?) -> Data? {
        switch kind ?? .files {
        case .files:
            let pathCoveragesWithDetails: [PathCoverageWithHtmlUrl] = pathCoverages.map { PathCoverageWithHtmlUrl(path: $0.path, percent: $0.percent, htmlUrl: "/html/coverage-file?id=\(resultIdentifier)&path=\($0.path)") }
            return try? JSONEncoder().encode(pathCoveragesWithDetails)
        case .paths:
            return try? JSONEncoder().encode(pathCoverages)
        }
    }
}

private extension CoverageRoute {
    struct PathCoverageWithHtmlUrl: Codable {
        let path: String
        let percent: Double
        let htmlUrl: String
    }

    enum Kind: String {
        case files, paths

        init?(queryItems: [URLQueryItem]) {
            guard let rawValue = queryItems.first(where: { $0.name == "kind" })?.value else {
                return nil
            }

            self.init(rawValue: rawValue)
        }
    }
}
