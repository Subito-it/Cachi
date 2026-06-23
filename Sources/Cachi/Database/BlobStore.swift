import CommonCrypto
import Foundation
import os

/// Content-addressed blob store for large binaries kept out of SQLite: transcoded videos,
/// gzipped session logs, and (if ever used) screenshots. Files live under
/// `<results-path>/.cachi-data/blobs/<ab>/<full-hash>` keyed by the SHA-256 of their bytes,
/// so identical content (e.g. the same failure frame across retries) is stored once.
///
/// SQLite holds the manifest (`blob` table + `*.blob_hash` columns); this type owns the bytes.
final class BlobStore {
    enum Kind: String {
        case video
        case sessionLog
        case screenshot
        case attachment
    }

    private let blobsUrl: URL
    private let database: Database
    private let writeLock = NSLock()

    init(baseUrl: URL, database: Database) {
        self.blobsUrl = Cachi.blobsUrl(baseUrl: baseUrl)
        self.database = database
        try? FileManager.default.createDirectory(at: blobsUrl, withIntermediateDirectories: true)
    }

    // MARK: - Hashing

    static func hash(of data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(ofFileAt url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        let bufferSize = 1 << 20
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 { return nil }
            if read == 0 { break }
            CC_SHA256_Update(&context, buffer, CC_LONG(read))
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Paths

    private func relativePath(for hash: String) -> String {
        let prefix = String(hash.prefix(2))
        return "\(prefix)/\(hash)"
    }

    func url(forHash hash: String) -> URL {
        blobsUrl.appendingPathComponent(relativePath(for: hash))
    }

    // MARK: - Store

    /// Stores `data`, returning its content hash. Deduplicates: if the hash already exists on
    /// disk and in the manifest, the bytes are not rewritten.
    @discardableResult
    func store(_ data: Data, kind: Kind) throws -> String {
        let hash = Self.hash(of: data)
        try persist(hash: hash, byteCount: data.count, kind: kind) { destination in
            try data.write(to: destination, options: .atomic)
        }
        return hash
    }

    /// Stores the file already produced at `fileUrl` (e.g. a transcoded video) by moving it into
    /// the store under its content hash. The source file is removed on success.
    @discardableResult
    func store(fileAt fileUrl: URL, kind: Kind) throws -> String {
        guard let hash = Self.hash(ofFileAt: fileUrl) else {
            throw CocoaError(.fileReadUnknown)
        }
        // `persist` invokes the closure only when the hash isn't already stored, so the move always
        // targets a free path. On a dedup hit the closure is skipped and the source is left behind —
        // remove it afterwards so callers don't have to.
        try persist(hash: hash, byteCount: byteCount(of: fileUrl), kind: kind) { destination in
            try FileManager.default.moveItem(at: fileUrl, to: destination)
        }
        try? FileManager.default.removeItem(at: fileUrl)
        return hash
    }

    private func persist(hash: String, byteCount: Int, kind: Kind, write: (URL) throws -> Void) throws {
        writeLock.lock()
        defer { writeLock.unlock() }

        let destination = url(forHash: hash)
        let alreadyOnDisk = FileManager.default.fileExists(atPath: destination.path)

        if !alreadyOnDisk {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(destination)
        }

        let relPath = relativePath(for: hash)
        try database.write { db in
            try db.run(
                "INSERT INTO blob (hash, rel_path, byte_size, created_at, kind) VALUES (?,?,?,?,?) ON CONFLICT(hash) DO NOTHING;",
                [.text(hash), .text(relPath), .integer(Int64(byteCount)), SQLiteValue(Date()), .text(kind.rawValue)]
            )
        }
    }

    private func byteCount(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    // MARK: - Retention

    /// Deletes blob files no longer referenced by any attachment or session_log row, and removes
    /// their manifest rows.
    func collectGarbage() {
        let referenced = Set(
            database.query("SELECT blob_hash AS h FROM attachment WHERE blob_hash IS NOT NULL").compactMap { $0.string("h") }
                + database.query("SELECT blob_hash AS h FROM session_log WHERE blob_hash IS NOT NULL").compactMap { $0.string("h") }
        )

        let all = database.query("SELECT hash, rel_path FROM blob")
        for row in all {
            guard let hash = row.string("hash"), !referenced.contains(hash) else { continue }
            if let relPath = row.string("rel_path") {
                try? FileManager.default.removeItem(at: blobsUrl.appendingPathComponent(relPath))
            }
            try? database.write { db in
                try db.run("DELETE FROM blob WHERE hash = ?;", [.text(hash)])
            }
        }
    }

    /// Caps total blob disk usage at `maxBytes` by deleting whole runs oldest-first (by
    /// `ingested_at`) until usage is under the limit, then GCs the now-unreferenced blobs.
    /// Deleting a `result_bundle` row cascades to its tests/activities/attachments/session logs, so
    /// the entire session is removed — not just its heavy blobs.
    ///
    /// **A run whose source `.xcresult` is still on disk is never evicted.** Its blobs are
    /// re-derivable from the bundle (via the read-through fallback) and its row is needed so the next
    /// parse's skip-check (`runIdentifier(forSourceUrls:)`) doesn't re-ingest and re-transcode it.
    /// Eviction therefore only reclaims runs that have already been pruned externally — for those the
    /// stored blobs are the *only* copy, so deletion is permanent. Bundle lifetime is managed by the
    /// external pruner; this just bounds disk for what it left behind.
    ///
    /// Usage is read from the per-run `blob_byte_size` rollup, which is maintained incrementally as
    /// blobs materialize (see the blob-hash setters in `ResultStore`). The cap is **approximate**: a blob
    /// deduplicated across runs is counted once per referencing run, so the rollup over-attributes
    /// shared content. This is deliberate — it keeps accounting to a single cheap counter and never
    /// scans the filesystem.
    func enforceDiskLimit(maxBytes: Int) {
        guard maxBytes > 0 else { return }

        var total = database.query("SELECT COALESCE(SUM(blob_byte_size), 0) AS total FROM result_bundle;")
            .first?.int("total") ?? 0
        guard total > maxBytes else { return }

        let runs = database.query("SELECT identifier, blob_byte_size, source_xcresult_paths FROM result_bundle ORDER BY ingested_at ASC;")
        var evicted = 0
        for run in runs {
            guard total > maxBytes else { break }
            guard let identifier = run.string("identifier") else { continue }
            // Leave runs whose bundle is still on disk untouched — their blobs self-heal and their
            // row must survive so the next parse skips them.
            if xcresultStillOnDisk(sourcePaths: run.string("source_xcresult_paths")) { continue }
            let size = run.int("blob_byte_size") ?? 0
            try? database.write { db in
                try db.run("DELETE FROM result_bundle WHERE identifier = ?;", [.text(identifier)])
            }
            total -= size
            evicted += 1
        }

        if evicted > 0 {
            os_log("Disk limit (%ld bytes) exceeded: evicted %ld oldest pruned run(s)", log: .default, type: .info, maxBytes, evicted)
            collectGarbage()
        }
    }

    /// Whether any of a run's source `.xcresult` bundles still exist on disk. `sourcePaths` is the
    /// newline-joined list stored in `result_bundle.source_xcresult_paths`.
    private func xcresultStillOnDisk(sourcePaths: String?) -> Bool {
        guard let sourcePaths else { return false }
        return sourcePaths
            .split(separator: "\n")
            .contains { FileManager.default.fileExists(atPath: String($0)) }
    }
}
