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
