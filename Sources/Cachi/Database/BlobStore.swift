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
        blobsUrl = Cachi.blobsUrl(baseUrl: baseUrl)
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

    func exists(hash: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forHash: hash).path)
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
        try persist(hash: hash, byteCount: byteCount(of: fileUrl), kind: kind) { destination in
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: fileUrl)
            } else {
                try FileManager.default.moveItem(at: fileUrl, to: destination)
            }
        }
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

    /// Tiered retention: drops heavy blobs (videos, logs) for runs older than `maxAgeDays`, while
    /// keeping all structured rows forever (the cheap history). Clears the referencing `blob_hash`
    /// columns so the model stays consistent, then GCs the now-unreferenced blob files.
    /// A miss on a pruned blob self-heals via the read-through fallback (re-extracts from the
    /// xcresult if it still exists).
    func enforceRetention(maxAgeDays: Int) {
        guard maxAgeDays > 0 else { return }
        let cutoff = Date().timeIntervalSince1970 - Double(maxAgeDays) * 86_400

        // Null out references on tests belonging to runs older than the cutoff.
        try? database.write { db in
            try db.run("""
            UPDATE attachment SET blob_hash = NULL WHERE test_id IN (
                SELECT t.id FROM test t JOIN result_bundle r ON r.identifier = t.result_identifier
                WHERE r.ingested_at < ?
            );
            """, [.real(cutoff)])
            try db.run("""
            UPDATE session_log SET blob_hash = NULL WHERE test_id IN (
                SELECT t.id FROM test t JOIN result_bundle r ON r.identifier = t.result_identifier
                WHERE r.ingested_at < ?
            );
            """, [.real(cutoff)])
        }

        collectGarbage()
    }

    /// Recomputes the per-run blob byte rollup (`result_bundle.blob_byte_size`) from the current
    /// manifest. Cheap: it sums the indexed `blob.byte_size` column, never stats the filesystem.
    /// Runs that share a deduplicated blob each count its full size — a deliberate simplification
    /// (the model assumes disk is consumed only by blobs, attributed per run).
    func recomputeRunBlobSizes() {
        try? database.write { db in
            try db.run("""
            UPDATE result_bundle SET blob_byte_size = (
                SELECT COALESCE(SUM(b.byte_size), 0) FROM blob b WHERE b.hash IN (
                    SELECT a.blob_hash FROM attachment a JOIN test t ON t.id = a.test_id
                    WHERE t.result_identifier = result_bundle.identifier AND a.blob_hash IS NOT NULL
                    UNION
                    SELECT s.blob_hash FROM session_log s JOIN test t ON t.id = s.test_id
                    WHERE t.result_identifier = result_bundle.identifier AND s.blob_hash IS NOT NULL
                )
            );
            """)
        }
    }

    /// Caps total blob disk usage at `maxBytes` by deleting whole runs oldest-first (by
    /// `ingested_at`) until the rollup is under the limit, then GCs the now-unreferenced blobs.
    /// Deleting a `result_bundle` row cascades to its tests/activities/attachments/session logs, so
    /// the entire session is removed — not just its heavy blobs. Refreshes the per-run rollup first
    /// so the decision uses up-to-date sizes (blobs materialize asynchronously after parse).
    func enforceDiskLimit(maxBytes: Int) {
        guard maxBytes > 0 else { return }

        recomputeRunBlobSizes()

        var total = database.query("SELECT COALESCE(SUM(blob_byte_size), 0) AS total FROM result_bundle;")
            .first?.int("total") ?? 0
        guard total > maxBytes else { return }

        let runs = database.query("SELECT identifier, blob_byte_size FROM result_bundle ORDER BY ingested_at ASC;")
        var evicted = 0
        for run in runs {
            guard total > maxBytes else { break }
            guard let identifier = run.string("identifier") else { continue }
            let size = run.int("blob_byte_size") ?? 0
            try? database.write { db in
                try db.run("DELETE FROM result_bundle WHERE identifier = ?;", [.text(identifier)])
            }
            total -= size
            evicted += 1
        }

        if evicted > 0 {
            os_log("Disk limit (%ld bytes) exceeded: evicted %ld oldest run(s)", log: .default, type: .info, maxBytes, evicted)
            collectGarbage()
        }
    }
}
