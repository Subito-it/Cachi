import CachiKit
import Foundation

struct AttachmentFileLocator {
    static func exportedFileUrl(resultIdentifier: String, testSummaryIdentifier: String, attachmentIdentifier: String) -> URL? {
        guard let test = State.shared.test(summaryIdentifier: testSummaryIdentifier) else {
            return nil
        }

        let fileManager = FileManager.default
        let destinationUrl = Cachi.temporaryFolderUrl
            .appendingPathComponent(resultIdentifier)
            .appendingPathComponent(attachmentIdentifier.md5Value)

        if !fileManager.fileExists(atPath: destinationUrl.path) {
            let cachi = CachiKit(url: test.xcresultUrl)
            try? fileManager.createDirectory(at: destinationUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try? cachi.export(identifier: attachmentIdentifier, destinationPath: destinationUrl.path)
        }

        guard fileManager.fileExists(atPath: destinationUrl.path) else {
            return nil
        }

        return destinationUrl
    }
}
