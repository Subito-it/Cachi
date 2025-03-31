import AVFoundation
import CachiKit
import Foundation
import os
import Vapor

struct XcResultDownloadRoute: Routable {
    static let path = "/v1/xcresult"

    let method = HTTPMethod.GET
    let description = "Download the original xcresult"

    func respond(to req: Request) throws -> Response {
        os_log("xcResult download request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "id" })?.value
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("xcResult download with id '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }

        guard let test = State.shared.test(summaryIdentifier: testSummaryIdentifier) else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let destinationUrl = Cachi.temporaryFolderUrl.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destinationUrl) }

        do {
            _ = try test.xcresultUrl.zip(to: destinationUrl)
        } catch {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let filename = "xcresult.zip"
        let headers = [
            ("Content-Type", "application/zip"),
            ("Accept-Ranges", "bytes"),
            ("Content-Disposition", value: "attachment; filename=\(filename)")
        ]

        let response = req.fileio.streamFile(at: destinationUrl.path(percentEncoded: false))
        for header in headers {
            response.headers.add(name: header.0, value: header.1)
        }

        return try Response(body: Response.Body(data: Data(contentsOf: destinationUrl, options: [.alwaysMapped])))
    }

    static func urlString(testSummaryIdentifier: String?) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "id", value: testSummaryIdentifier)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }
}

public extension URL {
    /// Creates a zip archive of the file or folder represented by this URL and returns a references to the zipped file
    ///
    /// - parameter dest: the destination URL; if nil, the destination will be this URL with ".zip" appended
    func zip(to dest: URL? = nil) throws -> URL {
        let destURL = dest ?? appendingPathExtension("zip")

        let fm = FileManager.default
        var isDir: ObjCBool = false

        let srcDir: URL
        let srcDirIsTemporary: Bool
        if isFileURL, fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue == true {
            // this URL is a directory: just zip it in-place
            srcDir = self
            srcDirIsTemporary = false
        } else {
            // otherwise we need to copy the simple file to a temporary directory in order for
            // NSFileCoordinatorReadingOptions.ForUploading to actually zip it up
            srcDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: srcDir, withIntermediateDirectories: true, attributes: nil)
            let tmpURL = srcDir.appendingPathComponent(lastPathComponent)
            try fm.copyItem(at: self, to: tmpURL)
            srcDirIsTemporary = true
        }

        let coord = NSFileCoordinator()
        var readError: NSError?
        var copyError: NSError?
        var errorToThrow: NSError?

        var readSucceeded = false
        // coordinateReadingItemAtURL is invoked synchronously, but the passed in zippedURL is only valid
        // for the duration of the block, so it needs to be copied out
        coord.coordinate(readingItemAt: srcDir,
                         options: NSFileCoordinator.ReadingOptions.forUploading,
                         error: &readError) {
            (zippedURL: URL) in
            readSucceeded = true
            // assert: read succeeded
            do {
                try fm.copyItem(at: zippedURL, to: destURL)
            } catch let caughtCopyError {
                copyError = caughtCopyError as NSError
            }
        }

        if let theReadError = readError, !readSucceeded {
            // assert: read failed, readError describes our reading error
            NSLog("%@", "zipping failed")
            errorToThrow = theReadError
        } else if readError == nil, !readSucceeded {
            NSLog("%@", "NSFileCoordinator has violated its API contract. It has errored without throwing an error object")
            errorToThrow = NSError(domain: Bundle.main.bundleIdentifier!, code: 0, userInfo: nil)
        } else if let theCopyError = copyError {
            // assert: read succeeded, copy failed
            NSLog("%@", "zipping succeeded but copying the zip file failed")
            errorToThrow = theCopyError
        }

        if srcDirIsTemporary {
            do {
                try fm.removeItem(at: srcDir)
            } catch {
                // Not going to throw, because we do have a valid output to return. We're going to rely on
                // the operating system to eventually cleanup the temporary directory.
                NSLog("%@", "Warning. Zipping succeeded but could not remove temporary directory afterwards")
            }
        }
        if let error = errorToThrow { throw error }
        return destURL
    }
}
