import Foundation
import HTTPKit
import os
import CachiKit

struct AttachmentRoute: Routable {
    let path = "/attachment"
    let description = "Attachment route, used for html rendering"
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("Attachment request received", log: .default, type: .info)
        
        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "result_id" })?.value,
              let attachmentIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let contentType = queryItems.first(where: { $0.name == "content_type" })?.value,
              resultIdentifier.count > 0, attachmentIdentifier.count > 0 else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
                
        let benchId = benchmarkStart()
        defer { os_log("Attachment with id '%@' in result bundle '%@' fetched in %fms", log: .default, type: .info, attachmentIdentifier, resultIdentifier, benchmarkStop(benchId)) }
        
        guard let result = State.shared.result(identifier: resultIdentifier) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let cachi = CachiKit(url: result.resultBundleUrl)
        
        let destinationUrl = Cachi.temporaryFolderUrl.appendingPathComponent("result-\(resultIdentifier)").appendingPathComponent(attachmentIdentifier.md5Value)
        let destinationPath = destinationUrl.path
        let filemanager = FileManager.default
        
        if !filemanager.fileExists(atPath: destinationPath) {
            try? filemanager.createDirectory(at: destinationUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try? cachi.export(identifier: attachmentIdentifier, destinationPath: destinationPath)
        }
            
        guard filemanager.fileExists(atPath: destinationPath),
              let fileData = try? Data(contentsOf: destinationUrl) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
        
        let res = HTTPResponse(headers: HTTPHeaders([("Content-Type", contentType)]), body: HTTPBody(data: fileData))
        return promise.succeed(res)
    }
}
