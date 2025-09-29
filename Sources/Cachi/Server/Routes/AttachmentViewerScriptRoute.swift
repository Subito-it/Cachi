import Foundation
import os
import Vapor

struct AttachmentViewerScriptRoute: Routable {
    static let path = "/attachment-viewer/script"

    let method = HTTPMethod.GET
    let description = "Attachment viewer script route, proxies JavaScript assets from disk"

    private let attachmentViewers: [String: AttachmentViewerConfiguration]

    init(attachmentViewers: [String: AttachmentViewerConfiguration]) {
        self.attachmentViewers = attachmentViewers
    }

    func respond(to req: Request) throws -> Response {
        os_log("Attachment viewer script request received", log: .default, type: .info)

        guard !attachmentViewers.isEmpty,
              let components = req.urlComponents(),
              let viewerExtension = components.queryItems?.first(where: { $0.name == "viewer" })?.value?.lowercased(),
              let viewer = attachmentViewers[viewerExtension]
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        do {
            let data = try Data(contentsOf: viewer.scriptUrl, options: .mappedIfSafe)
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "application/javascript; charset=utf-8")
            headers.add(name: .cacheControl, value: "no-store")
            return Response(status: .ok, headers: headers, body: .init(data: data))
        } catch {
            os_log("Failed to read attachment viewer script at %@: %@", log: .default, type: .error, viewer.scriptUrl.path, error.localizedDescription)
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Unable to load script"))
        }
    }

    static func urlString(viewerExtension: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "viewer", value: viewerExtension.lowercased()),
            .init(name: "ts", value: String(Int(Date().timeIntervalSince1970))) // bypass browser cache
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }
}
