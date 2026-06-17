import Foundation
import os

/// The single SQLite-backed store for all structured data and blob manifests.
///
/// Concurrency model: one serial writer queue (all mutations funnel through it) plus a
/// dedicated read connection guarded by its own lock. WAL mode lets readers proceed while
/// the writer is active. This mirrors the previous `State` barrier-write design but backed
/// by SQLite instead of an in-memory array.
final class Database {
    private let writer: SQLiteConnection
    private let writerQueue = DispatchQueue(label: "com.subito.cachi.db.writer")

    private let reader: SQLiteConnection
    private let readerLock = NSLock()

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

        reader = try SQLiteConnection(path: databaseUrl.path, readonly: true)
        try reader.execute("PRAGMA foreign_keys=ON;")
    }

    // MARK: - Write access

    /// Runs `body` on the serial writer queue. All mutations go through here.
    func write<T>(_ body: (SQLiteConnection) throws -> T) rethrows -> T {
        try writerQueue.sync { try body(writer) }
    }

    /// Wraps `body` in a transaction on the writer queue.
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

    /// Runs a read query. Serialized on the reader connection (WAL allows concurrency with the writer).
    func query(_ sql: String, _ bindings: [SQLiteValue] = []) -> [SQLiteRow] {
        readerLock.lock()
        defer { readerLock.unlock() }
        do {
            return try reader.query(sql, bindings)
        } catch {
            os_log("DB query failed: %@", log: .default, type: .error, "\(error)")
            return []
        }
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

        if current < 1 {
            try db.execute(Self.schemaV1)
            try db.run("DELETE FROM schema_version;")
            try db.run("INSERT INTO schema_version (version) VALUES (?);", [.integer(1)])
            os_log("Applied SQLite schema v1", log: .default, type: .info)
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
        source_xcresult_paths TEXT NOT NULL
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
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id   INTEGER NOT NULL REFERENCES test(id) ON DELETE CASCADE,
        parent_id INTEGER,
        uuid      TEXT,
        title     TEXT,
        type      TEXT,
        start     REAL,
        finish    REAL
    );

    CREATE TABLE failure (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id INTEGER NOT NULL REFERENCES test(id) ON DELETE CASCADE,
        message TEXT,
        file    TEXT,
        line    INTEGER,
        detail  TEXT
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
        filename     TEXT,
        uti          TEXT,
        name         TEXT,
        payload_ref  TEXT,
        payload_size INTEGER,
        content_type TEXT,
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
    CREATE INDEX idx_test_summary ON test(summary_identifier);
    CREATE INDEX idx_test_diag ON test(diagnostics_identifier);
    CREATE INDEX idx_test_route ON test(route_identifier, start_date DESC);
    CREATE INDEX idx_test_target_device ON test(target_name, device_model, device_os, start_date DESC);

    CREATE INDEX idx_activity_test ON activity(test_id);
    CREATE INDEX idx_attachment_test ON attachment(test_id);
    CREATE INDEX idx_session_log_test ON session_log(test_id);
    """
}
