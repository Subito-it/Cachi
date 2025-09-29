import Cachi
import XCTest

final class AttachmentViewerConfigurationTests: XCTestCase {
    func testParsesValidArgument() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let scriptUrl = temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("js")
        try "console.log('ok');".write(to: scriptUrl, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptUrl) }

        let configuration = try AttachmentViewerConfiguration(argumentValue: "json:\(scriptUrl.path)")

        XCTAssertEqual(configuration.fileExtension, "json")
        XCTAssertEqual(configuration.scriptUrl, scriptUrl.standardizedFileURL)
    }

    func testRejectsInvalidFormat() {
        XCTAssertThrowsError(try AttachmentViewerConfiguration(argumentValue: "invalid")) { error in
            guard case AttachmentViewerConfiguration.Error.invalidFormat = error else {
                return XCTFail("Expected invalidFormat error, received: \(error)")
            }
        }
    }

    func testRejectsMissingScript() {
        let nonexistentPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("js").path

        XCTAssertThrowsError(try AttachmentViewerConfiguration(argumentValue: "png:\(nonexistentPath)")) { error in
            guard case AttachmentViewerConfiguration.Error.scriptNotFound = error else {
                return XCTFail("Expected scriptNotFound error, received: \(error)")
            }
        }
    }

    static var allTests = [
        ("testParsesValidArgument", testParsesValidArgument),
        ("testRejectsInvalidFormat", testRejectsInvalidFormat),
        ("testRejectsMissingScript", testRejectsMissingScript)
    ]
}
