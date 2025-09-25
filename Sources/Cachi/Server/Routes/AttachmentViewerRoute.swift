import Foundation
import os
import Vapor

struct AttachmentViewerRoute: Routable {
    static let path = "/attachment-viewer"

    let method = HTTPMethod.GET
    let description = "Attachment viewer route, delivers an HTML wrapper for custom viewers"

    private let attachmentViewers: [String: AttachmentViewerConfiguration]

    init(attachmentViewers: [String: AttachmentViewerConfiguration]) {
        self.attachmentViewers = attachmentViewers
    }

    func respond(to req: Request) throws -> Response {
        os_log("Attachment viewer request received", log: .default, type: .info)

        guard !attachmentViewers.isEmpty,
              let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let viewerExtension = queryItems.first(where: { $0.name == "viewer" })?.value?.lowercased(),
              let viewer = attachmentViewers[viewerExtension],
              let resultIdentifier = queryItems.first(where: { $0.name == "result_id" })?.value,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "test_id" })?.value,
              let attachmentIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let filename = queryItems.first(where: { $0.name == "filename" })?.value,
              let contentType = queryItems.first(where: { $0.name == "content_type" })?.value
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        guard AttachmentFileLocator.exportedFileUrl(resultIdentifier: resultIdentifier,
                                                    testSummaryIdentifier: testSummaryIdentifier,
                                                    attachmentIdentifier: attachmentIdentifier) != nil
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let scriptSrc = AttachmentViewerScriptRoute.urlString(viewerExtension: viewer.fileExtension)
        let attachmentUrl = AttachmentRoute.urlString(identifier: attachmentIdentifier,
                                                      resultIdentifier: resultIdentifier,
                                                      testSummaryIdentifier: testSummaryIdentifier,
                                                      filename: filename,
                                                      contentType: contentType)

        let attachmentTitle = queryItems.first(where: { $0.name == "title" })?.value ?? filename
        let pageTitle = makeTitle(displayName: attachmentTitle)
        let html = makeHtmlDocument(title: pageTitle,
                                    scriptSrc: scriptSrc,
                                    attachmentUrl: attachmentUrl)

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        headers.add(name: .cacheControl, value: "no-store")

        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    private func makeTitle(displayName: String) -> String {
        let sanitizedName = displayName.removingPercentEncoding ?? displayName
        if sanitizedName.isEmpty {
            return "Cachi Attachment Viewer"
        }
        return "Cachi Attachment Viewer - \(sanitizedName)"
    }

    private func makeHtmlDocument(title: String,
                                  scriptSrc: String,
                                  attachmentUrl: String) -> String {
        let escapedTitle = title.replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <link rel="stylesheet" href="/css?main"/>
            <title>\(escapedTitle)</title>
          </head>
          <body>
            <div id="app"></div>
            <noscript>This app requires JavaScript.</noscript>
            <script>
              (function () {
                var s = document.createElement('script');
                s.src = '\(scriptSrc)';
                s.attachmentUrl = '\(attachmentUrl)';
                s.onload = function(){};
                document.body.appendChild(s);
              })();
            </script>
          </body>
        </html>
        """
    }

    private func escapeHtmlAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func urlString(viewerExtension: String,
                          resultIdentifier: String,
                          testSummaryIdentifier: String,
                          attachmentIdentifier: String,
                          filename: String,
                          title: String,
                          contentType: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "viewer", value: viewerExtension.lowercased()),
            .init(name: "result_id", value: resultIdentifier),
            .init(name: "test_id", value: testSummaryIdentifier),
            .init(name: "id", value: attachmentIdentifier),
            .init(name: "filename", value: filename),
            .init(name: "title", value: title),
            .init(name: "content_type", value: contentType)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }
}
