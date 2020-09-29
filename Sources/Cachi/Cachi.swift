import Foundation

enum Cachi {
    static let version = "12.0.0"
    static let cacheFolderName = ".Cachi"
    static let temporaryFolderUrl: URL = {
        let url = URL(fileURLWithPath: "/tmp").appendingPathComponent("Cachi")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }()
}
