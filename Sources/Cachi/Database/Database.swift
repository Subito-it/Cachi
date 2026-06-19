import Foundation
import os

/// The single SQLite-backed store for all structured data and blob manifests.
///
/// Concurrency model: one serial writer queue (all mutations funnel through it) plus a pool of
/// read-only connections. WAL mode lets all readers proceed concurrently with each other and with
/// the writer. Vapor serves requests concurrently, so a pool (rather than one shared reader) keeps
/// a slow query from blocking unrelated reads. The free-list lock only guards connection handoff —
/// query execution happens outside it.
final class Database {
    private let writer: SQLiteConnection
    private let writerQueue = DispatchQueue(label: "com.subito.cachi.db.writer")

    private let readers: [SQLiteConnection]
    private var availableReaders: [SQLiteConnection]
    private let readerPoolLock = NSLock()
    private let readerPoolSemaphore: DispatchSemaphore

    let databaseUrl: URL

    init(baseUrl: URL) throws {
        Cachi.createDataStore(baseUrl: baseUrl)
        databaseUrl = Cachi.databaseUrl(baseUrl: baseUrl)

        writer = try SQLiteConnection(path: databaseUrl.path, readonly: false)
        try writer.execute("PRAGMA journal_mode=WAL;")
        try writer.execute("PRAGMA synchronous=NORMAL;")
        try writer.execute("PRAGMA foreign_keys=ON;")
        try writer.execute("PRAGMA busy_timeout=5000;")

        try Self.migrate(writer)

        let readerCount = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))
        var pool = [SQLiteConnection]()
        for _ in 0 ..< readerCount {
            let reader = try SQLiteConnection(path: databaseUrl.path, readonly: true)
            try reader.execute("PRAGMA foreign_keys=ON;")
            try reader.execute("PRAGMA busy_timeout=5000;")
            pool.append(reader)
        }
        readers = pool
        availableReaders = pool
        readerPoolSemaphore = DispatchSemaphore(value: readerCount)
    }

    // MARK: - Write access
    //
    // NOT reentrant: `write`/`transaction` funnel through the serial `writerQueue` via `sync`, so a
    // `body` that calls back into `write`/`transaction` (directly or through a helper like
    // `blobStore.store`) deadlocks the queue on itself. Inside a `body`, operate on the passed
    // `SQLiteConnection` directly; never re-enter these methods.

    /// Runs `body` on the serial writer queue. All mutations go through here. See the reentrancy
    /// note above — `body` must not call `write`/`transaction` again.
    func write<T>(_ body: (SQLiteConnection) throws -> T) rethrows -> T {
        try writerQueue.sync { try body(writer) }
    }

    /// Wraps `body` in a transaction on the writer queue. See the reentrancy note above — `body`
    /// must not call `write`/`transaction` again.
    func transaction<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        try writerQueue.sync {
            try writer.execute("BEGIN IMMEDIATE;")
            do {
                let result = try body(writer)
                try writer.execute("COMMIT;")
                return result
            } catch {
                try? writer.execute("ROLLBACK;")
                throw error
            }
        }
    }

    // MARK: - Read access

    /// Runs a read query on a borrowed pooled connection. Concurrent callers each get their own
    /// connection (up to the pool size) and execute in parallel; the lock only guards borrow/return.
    ///
    /// On failure this returns an empty array so a single bad query degrades to an empty page rather
    /// than taking down request serving. The downside is that a genuine error (lock timeout, malformed
    /// SQL) then looks identical to "no rows" to the caller — so the failure is logged loudly with the
    /// offending SQL, and trips an assertion in debug builds to surface it during development.
    func query(_ sql: String, _ bindings: [SQLiteValue] = []) -> [SQLiteRow] {
        let reader = borrowReader()
        defer { returnReader(reader) }
        do {
            return try reader.query(sql, bindings)
        } catch {
            os_log("DB query failed (returning no rows): %@ — SQL: %@", log: .default, type: .fault, "\(error)", sql)
            assertionFailure("DB query failed: \(error) — SQL: \(sql)")
            return []
        }
    }

    private func borrowReader() -> SQLiteConnection {
        readerPoolSemaphore.wait()
        readerPoolLock.lock()
        defer { readerPoolLock.unlock() }
        return availableReaders.removeLast()
    }

    private func returnReader(_ reader: SQLiteConnection) {
        readerPoolLock.lock()
        availableReaders.append(reader)
        readerPoolLock.unlock()
        readerPoolSemaphore.signal()
    }

    // MARK: - Maintenance

    /// Cheap periodic hygiene: refresh query-planner stats and run incremental WAL checkpointing.
    func performMaintenance() {
        try? write { db in
            try db.execute("PRAGMA optimize;")
            try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        }
    }

    // MARK: - Migrations

    private static func migrate(_ db: SQLiteConnection) throws {
        try db.execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);")
        let current = (try db.query("SELECT version FROM schema_version LIMIT 1;").first?.int("version")) ?? 0

        try applyMigration(db, version: 1, ifBelow: current, sql: Self.schemaV1)
    }

    /// Applies one migration step atomically: the schema DDL/DML **and** the `schema_version` bump
    /// commit together, or roll back together on any failure. This prevents a half-applied migration
    /// (e.g. an `ALTER` that succeeded before a backfill threw) from wedging the DB — without the
    /// version advancing, the next launch would otherwise re-run the `ALTER` and fail on a duplicate
    /// column. Runs on the writer connection at init, before the writer queue serves anything, so
    /// driving `BEGIN`/`COMMIT` directly on the connection is safe.
    private static func applyMigration(_ db: SQLiteConnection, version: Int, ifBelow current: Int, sql: String) throws {
        guard current < version else { return }

        try db.execute("BEGIN IMMEDIATE;")
        do {
            try db.execute(sql)
            try db.run("DELETE FROM schema_version;")
            try db.run("INSERT INTO schema_version (version) VALUES (?);", [.integer(Int64(version))])
            try db.execute("COMMIT;")
            os_log("Applied SQLite schema v%ld", log: .default, type: .info, version)
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    private static let schemaV1 = """
    CREATE TABLE result_bundle (
        identifier            TEXT PRIMARY KEY,
        test_start_date       REAL NOT NULL,
        test_end_date         REAL NOT NULL,
        total_execution_time  REAL NOT NULL,
        destinations          TEXT NOT NULL,
        branch                TEXT,
        commit_hash           TEXT,
        commit_message        TEXT,
        metadata              TEXT,
        source_base_path      TEXT,
        github_base_url       TEXT,
        user_start_date       REAL,
        user_end_date         REAL,
        crash_count           INTEGER NOT NULL DEFAULT 0,
        ingested_at           REAL NOT NULL,
        source_xcresult_paths TEXT NOT NULL,
        -- per-run rollup of bytes occupied by its blobs (videos, session logs), so disk-size
        -- enforcement can attribute usage to runs and evict whole sessions without scanning the FS.
        blob_byte_size        INTEGER NOT NULL DEFAULT 0,
        -- derived rollups for the results-list endpoints, so the list view never reconstructs every
        -- `Test` and re-runs `ResultBundle.make`'s grouping per request. The counts come from
        -- `make`'s grouping logic (not a plain SQL `GROUP BY`), written at ingest in `upsert`.
        passed_count            INTEGER NOT NULL DEFAULT 0,
        uniquely_failed_count   INTEGER NOT NULL DEFAULT 0,
        failed_by_system_count  INTEGER NOT NULL DEFAULT 0,
        failed_retrying_count   INTEGER NOT NULL DEFAULT 0,
        total_count             INTEGER NOT NULL DEFAULT 0,
        summary_rollup_done     INTEGER NOT NULL DEFAULT 0,
        first_target_name       TEXT,
        first_device_model      TEXT,
        first_device_os         TEXT,
        -- cached "does this run have per-folder coverage on disk" flag so the results-list view skips
        -- a `FileManager.fileExists` probe per run per request. -1 = unknown, 0 = no, 1 = yes.
        has_coverage            INTEGER NOT NULL DEFAULT -1
    );

    CREATE TABLE test (
        id                     INTEGER PRIMARY KEY AUTOINCREMENT,
        result_identifier      TEXT NOT NULL REFERENCES result_bundle(identifier) ON DELETE CASCADE,
        xcresult_path          TEXT NOT NULL,
        test_identifier        TEXT NOT NULL,
        route_identifier       TEXT NOT NULL,
        summary_identifier     TEXT,
        diagnostics_identifier TEXT,
        target_name            TEXT NOT NULL,
        group_name             TEXT NOT NULL,
        group_identifier       TEXT NOT NULL,
        name                   TEXT NOT NULL,
        device_name            TEXT NOT NULL,
        device_model           TEXT NOT NULL,
        device_os              TEXT NOT NULL,
        device_identifier      TEXT NOT NULL,
        start_date             REAL NOT NULL,
        duration               REAL NOT NULL,
        status                 TEXT NOT NULL,
        is_system_failure      INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE activity (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id             INTEGER NOT NULL REFERENCES test(id) ON DELETE CASCADE,
        parent_id           INTEGER,
        uuid                TEXT,
        title               TEXT,
        type                TEXT,
        start               REAL,
        finish              REAL,
        failure_summary_ids TEXT
    );

    CREATE TABLE failure (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id   INTEGER NOT NULL REFERENCES test(id) ON DELETE CASCADE,
        message   TEXT,
        file      TEXT,
        line      INTEGER,
        detail    TEXT,
        uuid      TEXT,
        timestamp REAL
    );

    CREATE TABLE performance_metric (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id           INTEGER NOT NULL REFERENCES test(id) ON DELETE CASCADE,
        display_name      TEXT NOT NULL,
        unit              TEXT NOT NULL,
        measurements_json TEXT NOT NULL
    );

    CREATE TABLE attachment (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id      INTEGER NOT NULL REFERENCES test(id) ON DELETE CASCADE,
        activity_id  INTEGER,
        failure_id   INTEGER,
        filename     TEXT,
        uti          TEXT,
        name         TEXT,
        payload_ref  TEXT,
        payload_size INTEGER,
        content_type TEXT,
        timestamp    REAL,
        blob_hash    TEXT
    );

    CREATE TABLE session_log (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id   INTEGER NOT NULL REFERENCES test(id) ON DELETE CASCADE,
        kind      TEXT NOT NULL,
        blob_hash TEXT,
        byte_size INTEGER
    );

    CREATE TABLE blob (
        hash       TEXT PRIMARY KEY,
        rel_path   TEXT NOT NULL,
        byte_size  INTEGER NOT NULL,
        created_at REAL NOT NULL,
        kind       TEXT NOT NULL
    );

    CREATE INDEX idx_rb_start ON result_bundle(test_start_date DESC);

    CREATE INDEX idx_test_result ON test(result_identifier);
    CREATE UNIQUE INDEX idx_test_summary ON test(summary_identifier);
    CREATE INDEX idx_test_diag ON test(diagnostics_identifier);
    CREATE INDEX idx_test_route ON test(route_identifier, start_date DESC);
    CREATE INDEX idx_test_target_device ON test(target_name, device_model, device_os, start_date DESC);

    CREATE INDEX idx_activity_test ON activity(test_id);
    CREATE INDEX idx_attachment_test ON attachment(test_id);
    CREATE INDEX idx_session_log_test ON session_log(test_id);
    """
}
