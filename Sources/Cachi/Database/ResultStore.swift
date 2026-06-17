import Foundation
import os

/// Persists and reconstructs `ResultBundle` values to/from SQLite. This is the structured tier:
/// run metadata + the flat list of tests (the derived collections are recomputed on read via
/// `ResultBundle.make`). Heavy detail (activity tree, attachments, session logs) is written by
/// the ingest path into the detail tables and stays out of the in-memory model.
final class ResultStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    // MARK: - Write

    /// Upserts a whole result bundle (run row + its test rows). Idempotent on the run identifier:
    /// re-ingesting the same bundle replaces its rows.
    func upsert(_ bundle: ResultBundle) {
        let info = bundle.userInfo
        let sourcePaths = bundle.xcresultUrls.map(\.path).sorted().joined(separator: "\n")

        do {
            try database.transaction { db in
                // Replace any prior rows for this run so re-ingest is clean (CASCADE clears children).
                try db.run("DELETE FROM result_bundle WHERE identifier = ?;", [.text(bundle.identifier)])

                try db.run("""
                INSERT INTO result_bundle
                    (identifier, test_start_date, test_end_date, total_execution_time, destinations,
                     branch, commit_hash, commit_message, metadata, source_base_path, github_base_url,
                     user_start_date, user_end_date, crash_count, ingested_at, source_xcresult_paths)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
                """, [
                    .text(bundle.identifier),
                    SQLiteValue(bundle.testStartDate),
                    SQLiteValue(bundle.testEndDate),
                    .real(bundle.totalExecutionTime),
                    .text(bundle.destinations),
                    SQLiteValue(info?.branchName),
                    SQLiteValue(info?.commitHash),
                    SQLiteValue(info?.commitMessage),
                    SQLiteValue(info?.metadata),
                    SQLiteValue(info?.sourceBasePath),
                    SQLiteValue(info?.githubBaseUrl),
                    SQLiteValue(info?.startDate),
                    SQLiteValue(info?.endDate),
                    .integer(Int64(bundle.testsCrashCount)),
                    SQLiteValue(Date()),
                    .text(sourcePaths),
                ])

                for test in bundle.tests {
                    try db.run("""
                    INSERT INTO test
                        (result_identifier, xcresult_path, test_identifier, route_identifier,
                         summary_identifier, diagnostics_identifier, target_name, group_name,
                         group_identifier, name, device_name, device_model, device_os,
                         device_identifier, start_date, duration, status, is_system_failure)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
                    """, [
                        .text(bundle.identifier),
                        .text(test.xcresultUrl.path),
                        .text(test.identifier),
                        .text(test.routeIdentifier),
                        SQLiteValue(test.summaryIdentifier),
                        SQLiteValue(test.diagnosticsIdentifier),
                        .text(test.targetName),
                        .text(test.groupName),
                        .text(test.groupIdentifier),
                        .text(test.name),
                        .text(test.deviceName),
                        .text(test.deviceModel),
                        .text(test.deviceOs),
                        .text(test.deviceIdentifier),
                        SQLiteValue(test.testStartDate),
                        .real(test.duration),
                        .text(test.status.rawValue),
                        SQLiteValue(test.groupName == "System Failures"),
                    ])
                }
            }
        } catch {
            os_log("Failed persisting result bundle '%@': %@", log: .default, type: .error, bundle.identifier, "\(error)")
        }
    }

    func contains(identifier: String) -> Bool {
        !database.query("SELECT 1 FROM result_bundle WHERE identifier = ? LIMIT 1;", [.text(identifier)]).isEmpty
    }

    /// Looks up an already-ingested run by its source xcresult paths (the merge group). Used to
    /// skip re-parsing bundles already in the database. `urls` need not be pre-sorted.
    func runIdentifier(forSourceUrls urls: [URL]) -> String? {
        let key = urls.map(\.path).sorted().joined(separator: "\n")
        return database.query("SELECT identifier FROM result_bundle WHERE source_xcresult_paths = ? LIMIT 1;", [.text(key)])
            .first?.string("identifier")
    }

    func deleteAll() {
        try? database.write { db in
            try db.run("DELETE FROM result_bundle;")
            try db.run("DELETE FROM blob;")
        }
    }

    // MARK: - Detail extraction tracking

    /// Failed tests (incl. system failures) that still need detail extraction (activity tree,
    /// failures, attachment/session-log manifests). A test is considered done once it has any
    /// activity rows OR a session_log row — i.e. detail has been materialized at least once.
    func testsNeedingDetailExtraction() -> [(rowId: Int, test: ResultBundle.Test)] {
        let rows = database.query("""
        SELECT t.* FROM test t
        WHERE t.status = 'failure'
          AND NOT EXISTS (SELECT 1 FROM activity a WHERE a.test_id = t.id)
          AND NOT EXISTS (SELECT 1 FROM session_log s WHERE s.test_id = t.id)
        ORDER BY t.start_date DESC;
        """)
        return rows.compactMap { row in
            guard let id = row.int("id") else { return nil }
            return (id, test(from: row))
        }
    }

    func testRowId(summaryIdentifier: String) -> Int? {
        database.query("SELECT id FROM test WHERE summary_identifier = ? LIMIT 1;", [.text(summaryIdentifier)])
            .first?.int("id")
    }

    // MARK: - Blob materialization

    /// Video attachments (by UTI) for a test that have not yet been transcoded into the blob store.
    func videoAttachmentsNeedingBlob(testRowId: Int) -> [(attachmentId: Int, payloadRef: String)] {
        database.query("""
        SELECT id, payload_ref FROM attachment
        WHERE test_id = ? AND uti = 'public.mpeg-4' AND payload_ref IS NOT NULL AND blob_hash IS NULL;
        """, [.integer(Int64(testRowId))]).compactMap { row in
            guard let id = row.int("id"), let ref = row.string("payload_ref") else { return nil }
            return (id, ref)
        }
    }

    func sessionLogsNeedingBlob(testRowId: Int) -> [(logId: Int, kind: String)] {
        database.query("SELECT id, kind FROM session_log WHERE test_id = ? AND blob_hash IS NULL;",
                       [.integer(Int64(testRowId))]).compactMap { row in
            guard let id = row.int("id"), let kind = row.string("kind") else { return nil }
            return (id, kind)
        }
    }

    func setAttachmentBlobHash(attachmentId: Int, hash: String, contentType: String?) {
        try? database.write { db in
            try db.run("UPDATE attachment SET blob_hash = ?, content_type = ? WHERE id = ?;",
                       [.text(hash), SQLiteValue(contentType), .integer(Int64(attachmentId))])
        }
    }

    func setSessionLogBlobHash(logId: Int, hash: String, byteSize: Int) {
        try? database.write { db in
            try db.run("UPDATE session_log SET blob_hash = ?, byte_size = ? WHERE id = ?;",
                       [.text(hash), .integer(Int64(byteSize)), .integer(Int64(logId))])
        }
    }

    /// Looks up the stored blob hash for a test's video attachment / session-log channel, if any.
    func videoBlobHash(summaryIdentifier: String) -> String? {
        database.query("""
        SELECT a.blob_hash AS h FROM attachment a
        JOIN test t ON t.id = a.test_id
        WHERE t.summary_identifier = ? AND a.uti = 'public.mpeg-4' AND a.blob_hash IS NOT NULL
        LIMIT 1;
        """, [.text(summaryIdentifier)]).first?.string("h")
    }

    func sessionLogBlobHash(diagnosticsIdentifier: String, kind: String) -> String? {
        database.query("""
        SELECT s.blob_hash AS h FROM session_log s
        JOIN test t ON t.id = s.test_id
        WHERE t.diagnostics_identifier = ? AND s.kind = ? AND s.blob_hash IS NOT NULL
        LIMIT 1;
        """, [.text(diagnosticsIdentifier), .text(kind)]).first?.string("h")
    }

    // MARK: - Detail writes

    /// Persists the structured detail (activity tree, failures, perf metrics, attachment + session
    /// log manifests) for one test. Blob bytes are not stored here — `blob_hash` stays NULL until a
    /// background or on-demand pass materializes them.
    func writeDetail(testRowId: Int,
                     activities: [ActivityRow],
                     failures: [FailureRow],
                     attachments: [AttachmentRow],
                     sessionLogKinds: [String]) {
        do {
            try database.transaction { db in
                try db.run("DELETE FROM activity WHERE test_id = ?;", [.integer(Int64(testRowId))])
                try db.run("DELETE FROM failure WHERE test_id = ?;", [.integer(Int64(testRowId))])
                try db.run("DELETE FROM attachment WHERE test_id = ?;", [.integer(Int64(testRowId))])
                try db.run("DELETE FROM session_log WHERE test_id = ?;", [.integer(Int64(testRowId))])

                // Activities: insert depth-first so parent rows exist before children reference them.
                var dbIdByUuid = [String: Int64]()
                for activity in activities {
                    let parentDbId = activity.parentUuid.flatMap { dbIdByUuid[$0] }
                    try db.run("""
                    INSERT INTO activity (test_id, parent_id, uuid, title, type, start, finish)
                    VALUES (?,?,?,?,?,?,?);
                    """, [
                        .integer(Int64(testRowId)),
                        parentDbId.map { SQLiteValue.integer($0) } ?? .null,
                        SQLiteValue(activity.uuid),
                        SQLiteValue(activity.title),
                        SQLiteValue(activity.type),
                        SQLiteValue(activity.start),
                        SQLiteValue(activity.finish),
                    ])
                    if let uuid = activity.uuid {
                        dbIdByUuid[uuid] = db.lastInsertRowId
                    }
                }

                for failure in failures {
                    try db.run("""
                    INSERT INTO failure (test_id, message, file, line, detail) VALUES (?,?,?,?,?);
                    """, [
                        .integer(Int64(testRowId)),
                        SQLiteValue(failure.message),
                        SQLiteValue(failure.file),
                        SQLiteValue(failure.line),
                        SQLiteValue(failure.detail),
                    ])
                }

                for attachment in attachments {
                    try db.run("""
                    INSERT INTO attachment (test_id, activity_id, filename, uti, name, payload_ref, payload_size, content_type, blob_hash)
                    VALUES (?,?,?,?,?,?,?,?,NULL);
                    """, [
                        .integer(Int64(testRowId)),
                        attachment.activityUuid.flatMap { dbIdByUuid[$0] }.map { SQLiteValue.integer($0) } ?? .null,
                        SQLiteValue(attachment.filename),
                        SQLiteValue(attachment.uti),
                        SQLiteValue(attachment.name),
                        SQLiteValue(attachment.payloadRef),
                        SQLiteValue(attachment.payloadSize),
                        SQLiteValue(attachment.contentType),
                    ])
                }

                for kind in sessionLogKinds {
                    try db.run("INSERT INTO session_log (test_id, kind, blob_hash) VALUES (?,?,NULL);",
                               [.integer(Int64(testRowId)), .text(kind)])
                }
            }
        } catch {
            os_log("Failed writing detail for test row %ld: %@", log: .default, type: .error, testRowId, "\(error)")
        }
    }

    // MARK: - Row models for detail writes

    struct ActivityRow {
        let uuid: String?
        let parentUuid: String?
        let title: String?
        let type: String?
        let start: Date?
        let finish: Date?
    }

    struct FailureRow {
        let message: String?
        let file: String?
        let line: Int?
        let detail: String?
    }

    struct AttachmentRow {
        let activityUuid: String?
        let filename: String?
        let uti: String?
        let name: String?
        let payloadRef: String?
        let payloadSize: Int?
        let contentType: String?
    }

    // MARK: - Read

    /// Reconstructs all result bundles, newest first.
    func allResultBundles() -> [ResultBundle] {
        let runRows = database.query("SELECT * FROM result_bundle ORDER BY test_start_date DESC;")
        guard !runRows.isEmpty else { return [] }

        let testRows = database.query("SELECT * FROM test;")
        var testsByRun = [String: [ResultBundle.Test]]()
        for row in testRows {
            guard let runId = row.string("result_identifier") else { continue }
            testsByRun[runId, default: []].append(test(from: row))
        }

        return runRows.compactMap { bundle(from: $0, tests: testsByRun[$0.string("identifier") ?? ""] ?? []) }
    }

    func resultBundle(identifier: String) -> ResultBundle? {
        guard let runRow = database.query("SELECT * FROM result_bundle WHERE identifier = ?;", [.text(identifier)]).first else {
            return nil
        }
        let testRows = database.query("SELECT * FROM test WHERE result_identifier = ?;", [.text(identifier)])
        return bundle(from: runRow, tests: testRows.map(test(from:)))
    }

    func test(summaryIdentifier: String) -> ResultBundle.Test? {
        database.query("SELECT * FROM test WHERE summary_identifier = ? LIMIT 1;", [.text(summaryIdentifier)])
            .first.map(test(from:))
    }

    func test(diagnosticsIdentifier: String) -> ResultBundle.Test? {
        database.query("SELECT * FROM test WHERE diagnostics_identifier = ? LIMIT 1;", [.text(diagnosticsIdentifier)])
            .first.map(test(from:))
    }

    func tests(routeIdentifier: String, limit: Int) -> [ResultBundle.Test] {
        database.query("SELECT * FROM test WHERE route_identifier = ? ORDER BY start_date DESC LIMIT ?;",
                       [.text(routeIdentifier), .integer(Int64(limit))]).map(test(from:))
    }

    func allTargets() -> [String] {
        database.query("SELECT DISTINCT target_name FROM test ORDER BY target_name;")
            .compactMap { $0.string("target_name") }
    }

    func devices(inTarget target: String) -> [(model: String, os: String)] {
        database.query("SELECT DISTINCT device_model, device_os FROM test WHERE target_name = ?;", [.text(target)])
            .compactMap { row in
                guard let model = row.string("device_model"), let os = row.string("device_os") else { return nil }
                return (model, os)
            }
    }

    /// All tests for a target (newest first). Backs `allTests(in:)`.
    func statsTests(forTarget target: String) -> [ResultBundle.Test] {
        database.query("SELECT * FROM test WHERE target_name = ? ORDER BY start_date DESC;", [.text(target)])
            .map(test(from:))
    }

    /// Tests for the stats window: a given target/device, excluding system failures, newest first.
    func statsTests(target: String, deviceModel: String, deviceOs: String) -> [ResultBundle.Test] {
        database.query("""
        SELECT * FROM test
        WHERE target_name = ? AND device_model = ? AND device_os = ? AND group_name <> 'System Failures'
        ORDER BY start_date DESC;
        """, [.text(target), .text(deviceModel), .text(deviceOs)]).map(test(from:))
    }

    // MARK: - Row mapping

    private func bundle(from row: SQLiteRow, tests: [ResultBundle.Test]) -> ResultBundle? {
        guard let identifier = row.string("identifier") else { return nil }

        let hasUserInfo = row.string("branch") != nil || row.string("commit_hash") != nil
            || row.string("commit_message") != nil || row.string("metadata") != nil
            || row.string("source_base_path") != nil || row.string("github_base_url") != nil
            || row.date("user_start_date") != nil || row.date("user_end_date") != nil
        let userInfo: ResultBundle.UserInfo? = hasUserInfo ? ResultBundle.UserInfo(
            branchName: row.string("branch"),
            commitMessage: row.string("commit_message"),
            commitHash: row.string("commit_hash"),
            metadata: row.string("metadata"),
            sourceBasePath: row.string("source_base_path"),
            githubBaseUrl: row.string("github_base_url"),
            startDate: row.date("user_start_date"),
            endDate: row.date("user_end_date"),
            xcresultPathToFailedTestName: nil
        ) : nil

        let urls = Set((row.string("source_xcresult_paths") ?? "")
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) })

        var rebuilt = ResultBundle.make(identifier: identifier,
                                        xcresultUrls: urls,
                                        destinations: row.string("destinations") ?? "",
                                        totalExecutionTime: row.double("total_execution_time") ?? 0,
                                        tests: tests,
                                        testsCrashCount: row.int("crash_count") ?? 0,
                                        userInfo: userInfo)
        // Preserve the stored run window (don't let an empty test list zero it out).
        if let start = row.date("test_start_date") { rebuilt.testStartDate = start }
        if let end = row.date("test_end_date") { rebuilt.testEndDate = end }
        return rebuilt
    }

    private func test(from row: SQLiteRow) -> ResultBundle.Test {
        let summaryIdentifier = row.string("summary_identifier")
        return ResultBundle.Test(
            xcresultUrl: URL(fileURLWithPath: row.string("xcresult_path") ?? ""),
            identifier: row.string("test_identifier") ?? "",
            routeIdentifier: row.string("route_identifier") ?? "",
            url: "\(TestRoute.path)?\(summaryIdentifier ?? "")",
            html_url: "\(TestRouteHTML.path)?id=\(summaryIdentifier ?? "")",
            targetName: row.string("target_name") ?? "",
            groupName: row.string("group_name") ?? "",
            groupIdentifier: row.string("group_identifier") ?? "",
            name: row.string("name") ?? "",
            testStartDate: row.date("start_date") ?? Date(timeIntervalSince1970: 0),
            duration: row.double("duration") ?? 0,
            status: ResultBundle.Test.Status(rawValue: row.string("status") ?? "failure") ?? .failure,
            deviceName: row.string("device_name") ?? "",
            deviceModel: row.string("device_model") ?? "",
            deviceOs: row.string("device_os") ?? "",
            deviceIdentifier: row.string("device_identifier") ?? "",
            diagnosticsIdentifier: row.string("diagnostics_identifier"),
            summaryIdentifier: summaryIdentifier
        )
    }
}
