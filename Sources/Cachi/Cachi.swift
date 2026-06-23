import Foundation

enum Cachi {
    static let cacheFolderName = ".Cachi"
    static let dataFolderName = ".cachi-data"
    static let version = "26.0.0"
    static let temporaryFolderUrl: URL = {
        let url = URL(fileURLWithPath: "/tmp").appendingPathComponent("Cachi")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }()

    /// Persistent data store directory, located inside the results path passed on launch.
    /// Holds the SQLite database and the content-addressed blob store. Survives external
    /// pruning of dated run folders because it is a sibling of them.
    static func dataStoreUrl(baseUrl: URL) -> URL {
        baseUrl.appendingPathComponent(dataFolderName)
    }

    static func databaseUrl(baseUrl: URL) -> URL {
        dataStoreUrl(baseUrl: baseUrl).appendingPathComponent("cachi.sqlite")
    }

    static func blobsUrl(baseUrl: URL) -> URL {
        dataStoreUrl(baseUrl: baseUrl).appendingPathComponent("blobs")
    }

    /// Creates the data store directory tree if needed.
    @discardableResult
    static func createDataStore(baseUrl: URL) -> URL {
        let url = dataStoreUrl(baseUrl: baseUrl)
        try? FileManager.default.createDirectory(at: blobsUrl(baseUrl: baseUrl), withIntermediateDirectories: true)
        return url
    }
}
