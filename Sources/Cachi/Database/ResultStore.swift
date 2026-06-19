import CachiKit
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

                let firstTest = bundle.tests.first
                try db.run("""
                INSERT INTO result_bundle
                    (identifier, test_start_date, test_end_date, total_execution_time, destinations,
                     branch, commit_hash, commit_message, metadata, source_base_path, github_base_url,
                     user_start_date, user_end_date, crash_count, ingested_at, source_xcresult_paths,
                     passed_count, uniquely_failed_count, failed_by_system_count, failed_retrying_count,
                     total_count, first_target_name, first_device_model, first_device_os)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
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
                    .integer(Int64(bundle.testsPassed.count)),
                    .integer(Int64(bundle.testsUniquelyFailed.count)),
                    .integer(Int64(bundle.testsFailedBySystem.count)),
                    .integer(Int64(bundle.testsFailedRetring.count)),
                    .integer(Int64(bundle.tests.count)),
                    SQLiteValue(firstTest?.targetName),
                    SQLiteValue(firstTest?.deviceModel),
                    SQLiteValue(firstTest?.deviceOs),
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
        try? database.transaction { db in
            // Only fold the blob's size into the run rollup on the NULL→set transition, so an
            // idempotent re-set (e.g. serve-path materialization) never double-counts.
            let wasUnset = try !db.query("SELECT 1 FROM attachment WHERE id = ? AND blob_hash IS NULL;",
                                         [.integer(Int64(attachmentId))]).isEmpty
            try db.run("UPDATE attachment SET blob_hash = ?, content_type = ? WHERE id = ?;",
                       [.text(hash), SQLiteValue(contentType), .integer(Int64(attachmentId))])
            if wasUnset {
                try db.run("""
                UPDATE result_bundle SET blob_byte_size = blob_byte_size +
                    (SELECT COALESCE(byte_size, 0) FROM blob WHERE hash = ?)
                WHERE identifier =
                    (SELECT t.result_identifier FROM attachment a JOIN test t ON t.id = a.test_id WHERE a.id = ?);
                """, [.text(hash), .integer(Int64(attachmentId))])
            }
        }
    }

    func setSessionLogBlobHash(logId: Int, hash: String) {
        try? database.transaction { db in
            let wasUnset = try !db.query("SELECT 1 FROM session_log WHERE id = ? AND blob_hash IS NULL;",
                                         [.integer(Int64(logId))]).isEmpty
            try db.run("UPDATE session_log SET blob_hash = ? WHERE id = ?;",
                       [.text(hash), .integer(Int64(logId))])
            if wasUnset {
                try db.run("""
                UPDATE result_bundle SET blob_byte_size = blob_byte_size +
                    (SELECT COALESCE(byte_size, 0) FROM blob WHERE hash = ?)
                WHERE identifier =
                    (SELECT t.result_identifier FROM session_log s JOIN test t ON t.id = s.test_id WHERE s.id = ?);
                """, [.text(hash), .integer(Int64(logId))])
            }
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
                     performanceMetrics: [PerformanceMetricRow],
                     attachments: [AttachmentRow],
                     sessionLogKinds: [String]) {
        do {
            try database.transaction { db in
                try db.run("DELETE FROM activity WHERE test_id = ?;", [.integer(Int64(testRowId))])
                try db.run("DELETE FROM failure WHERE test_id = ?;", [.integer(Int64(testRowId))])
                try db.run("DELETE FROM performance_metric WHERE test_id = ?;", [.integer(Int64(testRowId))])
                try db.run("DELETE FROM attachment WHERE test_id = ?;", [.integer(Int64(testRowId))])
                try db.run("DELETE FROM session_log WHERE test_id = ?;", [.integer(Int64(testRowId))])

                // Activities: insert depth-first so parent rows exist before children reference them.
                var activityDbIdByUuid = [String: Int64]()
                for activity in activities {
                    let parentDbId = activity.parentUuid.flatMap { activityDbIdByUuid[$0] }
                    let failureIdsJson = activity.failureSummaryIDs.isEmpty
                        ? nil
                        : (try? String(decoding: JSONEncoder().encode(activity.failureSummaryIDs), as: UTF8.self))
                    try db.run("""
                    INSERT INTO activity (test_id, parent_id, uuid, title, type, start, finish, failure_summary_ids)
                    VALUES (?,?,?,?,?,?,?,?);
                    """, [
                        .integer(Int64(testRowId)),
                        parentDbId.map { SQLiteValue.integer($0) } ?? .null,
                        SQLiteValue(activity.uuid),
                        SQLiteValue(activity.title),
                        SQLiteValue(activity.type),
                        SQLiteValue(activity.start),
                        SQLiteValue(activity.finish),
                        SQLiteValue(failureIdsJson),
                    ])
                    if let uuid = activity.uuid {
                        activityDbIdByUuid[uuid] = db.lastInsertRowId
                    }
                }

                var failureDbIdByUuid = [String: Int64]()
                for failure in failures {
                    try db.run("""
                    INSERT INTO failure (test_id, message, file, line, detail, uuid, timestamp) VALUES (?,?,?,?,?,?,?);
                    """, [
                        .integer(Int64(testRowId)),
                        SQLiteValue(failure.message),
                        SQLiteValue(failure.file),
                        SQLiteValue(failure.line),
                        SQLiteValue(failure.detail),
                        .text(failure.uuid),
                        SQLiteValue(failure.timestamp),
                    ])
                    failureDbIdByUuid[failure.uuid] = db.lastInsertRowId
                }

                for metric in performanceMetrics {
                    let measurementsJson = (try? String(decoding: JSONEncoder().encode(metric.measurements), as: UTF8.self)) ?? "[]"
                    try db.run("""
                    INSERT INTO performance_metric (test_id, display_name, unit, measurements_json) VALUES (?,?,?,?);
                    """, [
                        .integer(Int64(testRowId)),
                        .text(metric.displayName),
                        .text(metric.unit),
                        .text(measurementsJson),
                    ])
                }

                for attachment in attachments {
                    let activityId: SQLiteValue
                    let failureId: SQLiteValue
                    switch attachment.owner {
                    case let .activity(uuid):
                        activityId = activityDbIdByUuid[uuid].map { SQLiteValue.integer($0) } ?? .null
                        failureId = .null
                    case let .failure(uuid):
                        activityId = .null
                        failureId = failureDbIdByUuid[uuid].map { SQLiteValue.integer($0) } ?? .null
                    }
                    try db.run("""
                    INSERT INTO attachment (test_id, activity_id, failure_id, filename, uti, name, payload_ref, payload_size, content_type, timestamp, blob_hash)
                    VALUES (?,?,?,?,?,?,?,?,?,?,NULL);
                    """, [
                        .integer(Int64(testRowId)),
                        activityId,
                        failureId,
                        SQLiteValue(attachment.filename),
                        SQLiteValue(attachment.uti),
                        SQLiteValue(attachment.name),
                        SQLiteValue(attachment.payloadRef),
                        SQLiteValue(attachment.payloadSize),
                        SQLiteValue(attachment.contentType),
                        SQLiteValue(attachment.timestamp),
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
        let failureSummaryIDs: [String]
    }

    struct FailureRow {
        let uuid: String
        let message: String?
        let file: String?
        let line: Int?
        let detail: String?
        let timestamp: Date?
    }

    struct PerformanceMetricRow {
        let displayName: String
        let unit: String
        let measurements: [Double]
    }

    struct AttachmentRow {
        enum Owner {
            case activity(String)  // activity uuid
            case failure(String)   // failure uuid
        }

        let owner: Owner
        let filename: String?
        let uti: String?
        let name: String?
        let payloadRef: String?
        let payloadSize: Int?
        let contentType: String?
        let timestamp: Date?
    }

    // MARK: - Summary reconstruction

    /// Rebuilds the CachiKit `ActionTestSummary` (activity tree, failures, attachments, performance
    /// metrics) from the structured detail tables, so the test-detail routes can serve it without
    /// the `.xcresult`. Returns nil when no detail has been extracted for the test yet (the caller
    /// then falls back to live extraction from the bundle).
    func reconstructTestSummary(summaryIdentifier: String) -> ActionTestSummary? {
        guard let testRow = database.query("SELECT id, name, status, duration FROM test WHERE summary_identifier = ? LIMIT 1;",
                                           [.text(summaryIdentifier)]).first,
              let testRowId = testRow.int("id")
        else {
            return nil
        }

        let activityRows = database.query("""
        SELECT id, parent_id, uuid, title, type, start, finish, failure_summary_ids
        FROM activity WHERE test_id = ? ORDER BY id ASC;
        """, [.integer(Int64(testRowId))])

        let failureRows = database.query("""
        SELECT id, uuid, message, file, line, detail, timestamp FROM failure WHERE test_id = ?;
        """, [.integer(Int64(testRowId))])

        // No structured detail materialized yet → signal a miss so the caller reads live.
        guard !activityRows.isEmpty || !failureRows.isEmpty else { return nil }

        let attachmentRows = database.query("""
        SELECT activity_id, failure_id, filename, uti, name, payload_ref, payload_size, timestamp
        FROM attachment WHERE test_id = ?;
        """, [.integer(Int64(testRowId))])

        let metricRows = database.query("""
        SELECT display_name, unit, measurements_json FROM performance_metric WHERE test_id = ?;
        """, [.integer(Int64(testRowId))])

        // Group attachments by their owning activity / failure db row id.
        var attachmentsByActivityId = [Int: [ActionTestAttachment]]()
        var attachmentsByFailureId = [Int: [ActionTestAttachment]]()
        for row in attachmentRows {
            let attachment = attachment(from: row)
            if let activityId = row.int("activity_id") {
                attachmentsByActivityId[activityId, default: []].append(attachment)
            } else if let failureId = row.int("failure_id") {
                attachmentsByFailureId[failureId, default: []].append(attachment)
            }
        }

        // Rebuild the activity tree from the flat parent_id-linked rows.
        var childrenByParentId = [Int: [SQLiteRow]]()
        var roots = [SQLiteRow]()
        for row in activityRows {
            if let parentId = row.int("parent_id") {
                childrenByParentId[parentId, default: []].append(row)
            } else {
                roots.append(row)
            }
        }

        func buildActivity(_ row: SQLiteRow) -> ActionTestActivitySummary {
            let id = row.int("id") ?? -1
            let subactivities = (childrenByParentId[id] ?? []).map(buildActivity)
            let failureSummaryIDs = row.string("failure_summary_ids")
                .flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
            return ActionTestActivitySummary(title: row.string("title"),
                                             activityType: row.string("type") ?? "",
                                             uuid: row.string("uuid") ?? "",
                                             start: row.date("start"),
                                             finish: row.date("finish"),
                                             attachments: attachmentsByActivityId[id] ?? [],
                                             subactivities: subactivities,
                                             failureSummaryIDs: failureSummaryIDs)
        }

        let activitySummaries = roots.map(buildActivity)

        let failureSummaries = failureRows.map { row -> ActionTestFailureSummary in
            let id = row.int("id") ?? -1
            return ActionTestFailureSummary(message: row.string("message"),
                                            fileName: row.string("file"),
                                            lineNumber: row.int("line"),
                                            uuid: row.string("uuid") ?? "missing-uuid",
                                            detailedDescription: row.string("detail"),
                                            attachments: attachmentsByFailureId[id] ?? [],
                                            timestamp: row.date("timestamp"))
        }

        let performanceMetrics = metricRows.map { row -> ActionTestPerformanceMetricSummary in
            let measurements = row.string("measurements_json")
                .flatMap { try? JSONDecoder().decode([Double].self, from: Data($0.utf8)) } ?? []
            return ActionTestPerformanceMetricSummary(displayName: row.string("display_name") ?? "",
                                                      unitOfMeasurement: row.string("unit") ?? "",
                                                      measurements: measurements)
        }

        return ActionTestSummary(identifier: summaryIdentifier,
                                 name: testRow.string("name") ?? "",
                                 testStatus: testRow.string("status") ?? "",
                                 duration: testRow.double("duration"),
                                 performanceMetrics: performanceMetrics,
                                 failureSummaries: failureSummaries,
                                 activitySummaries: activitySummaries)
    }

    private func attachment(from row: SQLiteRow) -> ActionTestAttachment {
        let payloadRef = row.string("payload_ref").map { Reference(id: $0) }
        return ActionTestAttachment(uniformTypeIdentifier: row.string("uti") ?? "",
                                    name: row.string("name"),
                                    timestamp: row.date("timestamp"),
                                    filename: row.string("filename"),
                                    payloadRef: payloadRef,
                                    payloadSize: row.int("payload_size"))
    }

    // MARK: - Result summaries (results-list endpoints)

    /// Lightweight per-run rollup for the results-list views. Read straight from `result_bundle`
    /// (no `test` join, no `ResultBundle.make`), so list cost scales with the number of runs, not the
    /// total number of tests across all history.
    struct ResultSummary {
        let identifier: String
        let testStartDate: Date
        let testEndDate: Date
        let startDate: Date
        let endDate: Date
        let destinations: String
        let branchName: String?
        let commitHash: String?
        let commitMessage: String?
        let metadata: String?
        let firstTargetName: String?
        let firstDeviceModel: String?
        let firstDeviceOs: String?
        let passedCount: Int
        let uniquelyFailedCount: Int
        let failedBySystemCount: Int
        let failedRetryingCount: Int
        let totalCount: Int
        let crashCount: Int
        let hasCoverage: Bool
    }

    /// All run summaries, newest first. One indexed scan of `result_bundle`; no test rows touched.
    /// Resolves any rows whose `has_coverage` is still unknown (-1) with a one-time filesystem
    /// probe, caching the answer back so subsequent requests never touch the filesystem.
    func resultSummaries() -> [ResultSummary] {
        let rows = database.query("SELECT * FROM result_bundle ORDER BY test_start_date DESC;")
        resolveUnknownCoverage(in: rows)
        return rows.map(summary(from:))
    }

    /// Records whether a run's per-folder coverage JSON exists on disk, so the results list reads a
    /// cached flag instead of probing the filesystem per request. Called when coverage generation
    /// finishes (and during the lazy resolve of rows still marked unknown).
    func setHasCoverage(identifier: String, hasCoverage: Bool) {
        try? database.write { db in
            try db.run("UPDATE result_bundle SET has_coverage = ? WHERE identifier = ?;",
                       [.integer(hasCoverage ? 1 : 0), .text(identifier)])
        }
    }

    /// One-time probe for rows still marked unknown (-1, i.e. ingested before their coverage
    /// finished generating). Resolves and caches each so the hot path stays filesystem-free.
    private func resolveUnknownCoverage(in rows: [SQLiteRow]) {
        for row in rows where (row.int("has_coverage") ?? -1) < 0 {
            guard let identifier = row.string("identifier") else { continue }
            setHasCoverage(identifier: identifier, hasCoverage: coverageExistsOnDisk(row: row))
        }
    }

    private func coverageExistsOnDisk(row: SQLiteRow) -> Bool {
        let coveragePath = (row.string("source_xcresult_paths") ?? "")
            .split(separator: "\n").first
            .map { URL(fileURLWithPath: String($0)).deletingLastPathComponent().appendingPathComponent("coverage-folders.json").path }
        return coveragePath.map { FileManager.default.fileExists(atPath: $0) } ?? false
    }

    private func summary(from row: SQLiteRow) -> ResultSummary {
        // -1 (unknown) is resolved by `resolveUnknownCoverage` before mapping; treat any leftover
        // negative as "no coverage".
        let hasCoverage = (row.int("has_coverage") ?? 0) == 1

        return ResultSummary(
            identifier: row.string("identifier") ?? "",
            testStartDate: row.date("test_start_date") ?? Date(timeIntervalSince1970: 0),
            testEndDate: row.date("test_end_date") ?? Date(timeIntervalSince1970: 0),
            startDate: row.date("user_start_date") ?? row.date("test_start_date") ?? Date(timeIntervalSince1970: 0),
            endDate: row.date("user_end_date") ?? row.date("test_end_date") ?? Date(timeIntervalSince1970: 0),
            destinations: row.string("destinations") ?? "",
            branchName: row.string("branch"),
            commitHash: row.string("commit_hash"),
            commitMessage: row.string("commit_message"),
            metadata: row.string("metadata"),
            firstTargetName: row.string("first_target_name"),
            firstDeviceModel: row.string("first_device_model"),
            firstDeviceOs: row.string("first_device_os"),
            passedCount: row.int("passed_count") ?? 0,
            uniquelyFailedCount: row.int("uniquely_failed_count") ?? 0,
            failedBySystemCount: row.int("failed_by_system_count") ?? 0,
            failedRetryingCount: row.int("failed_retrying_count") ?? 0,
            totalCount: row.int("total_count") ?? 0,
            crashCount: row.int("crash_count") ?? 0,
            hasCoverage: hasCoverage
        )
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

    /// Fully reconstructs the (at most `limit`) most recent runs that contain a test matching
    /// `routeIdentifier`, newest first. Each returned bundle has its complete test list so the
    /// derived collections (e.g. `testsUniquelyFailed`) the HTML stats page renders are correct.
    func resultBundles(containingRouteIdentifier routeIdentifier: String, limit: Int) -> [ResultBundle] {
        let runIdRows = database.query("""
        SELECT DISTINCT t.result_identifier AS rid, r.test_start_date AS sd
        FROM test t JOIN result_bundle r ON r.identifier = t.result_identifier
        WHERE t.route_identifier = ?
        ORDER BY r.test_start_date DESC
        LIMIT ?;
        """, [.text(routeIdentifier), .integer(Int64(limit))])

        return runIdRows.compactMap { $0.string("rid") }.compactMap { resultBundle(identifier: $0) }
    }

    func test(summaryIdentifier: String) -> ResultBundle.Test? {
        database.query("SELECT * FROM test WHERE summary_identifier = ? LIMIT 1;", [.text(summaryIdentifier)])
            .first.map(test(from:))
    }

    /// A test plus the fully reconstructed run it belongs to, found by summary identifier. The
    /// detail/session-log HTML pages need both (the run supplies `userInfo`, `identifier`, and the
    /// derived collections used for prev/next navigation). Indexed lookups, no corpus scan.
    func testWithResultBundle(summaryIdentifier: String) -> (test: ResultBundle.Test, resultBundle: ResultBundle)? {
        guard let row = database.query("SELECT * FROM test WHERE summary_identifier = ? LIMIT 1;", [.text(summaryIdentifier)]).first,
              let runId = row.string("result_identifier"),
              let resultBundle = resultBundle(identifier: runId)
        else {
            return nil
        }
        return (test(from: row), resultBundle)
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
