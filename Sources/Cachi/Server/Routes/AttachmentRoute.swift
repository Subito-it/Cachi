import CachiKit
import Foundation
import os
import Vapor

struct AttachmentRoute: Routable {
    static let path = "/attachment"
    
    let method = HTTPMethod.GET
    let description = "Attachment route, used for html rendering"

    func respond(to req: Request) throws -> Response {
        os_log("Attachment request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "result_id" })?.value,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "test_id" })?.value,
              let attachmentIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let contentType = queryItems.first(where: { $0.name == "content_type" })?.value,
              resultIdentifier.count > 0, attachmentIdentifier.count > 0
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Attachment with id '%@' in result bundle '%@' fetched in %fms", log: .default, type: .info, attachmentIdentifier, resultIdentifier, benchmarkStop(benchId)) }

        guard let test = State.shared.test(summaryIdentifier: testSummaryIdentifier) else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let destinationUrl = Cachi.temporaryFolderUrl.appendingPathComponent(resultIdentifier).appendingPathComponent(attachmentIdentifier.md5Value)
        let destinationPath = destinationUrl.path
        let filemanager = FileManager.default

        if !filemanager.fileExists(atPath: destinationPath) {
            let cachi = CachiKit(url: test.xcresultUrl)
            try? filemanager.createDirectory(at: destinationUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try? cachi.export(identifier: attachmentIdentifier, destinationPath: destinationPath)
        }

        guard filemanager.fileExists(atPath: destinationPath) else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        var headers = [
            ("Content-Type", contentType),
        ]
        
        if let filename = queryItems.first(where: { $0.name == "filename" })?.value?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let fileAttributes = try? FileManager.default.attributesOfItem(atPath: destinationPath),
           let bytes = fileAttributes[.size] as? Int64,
           bytes > 100 * 1024 {
            headers.append(("Content-Disposition", value: "attachment; filename=\(filename)"))
        }

        let response = Response(body: Response.Body(data: try! Data(contentsOf: URL(fileURLWithPath: destinationPath))))
        for header in headers {
            response.headers.add(name: header.0, value: header.1)
        }

        return response
    }
}
