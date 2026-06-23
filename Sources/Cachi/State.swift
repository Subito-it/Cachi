import CachiKit
import Foundation
import os
import ZippyJSON

class State {
    struct Device: Codable, Hashable, CustomStringConvertible {
        let model: String
        let os: String

        var description: String {
            "\(model) - \(os)"
        }

        init(model: String, os: String) {
            self.model = model
            self.os = os
        }

        init?(rawDescription: String?) {
            let components = rawDescription?.components(separatedBy: " - ") ?? []
            guard components.count == 2,
                  let model = components.first,
                  let os = components.last
            else {
                return nil
            }

            self.model = model
            self.os = os
        }
    }

    static let shared = State()

    static let defaultStatWindowSize = 20

    /// Optional cap (bytes) on total blob disk usage, set once from the launch argument. When set,
    /// each parse pass evicts whole runs oldest-first until usage is under this limit. nil = no cap.
    var maxDiskSizeBytes: Int?

    /// The persistent SQLite-backed store. Configured once on first parse (it needs the results
    /// `baseUrl`). All structured reads/writes go through it — there is no in-memory bundle corpus.
    private var store: ResultStore?
    private var database: Database?
    private var blobStore: BlobStore?
    private var backgroundIngest: BackgroundIngest?
    private(set) var baseUrl: URL?

    enum Status { case ready, parsing(progress: Double) }
    private var _state: Status
    var state: Status {
        syncQueue.sync { _state }
    }

    private let syncQueue = DispatchQueue(label: String(describing: State.self), attributes: .concurrent)

    init() {
        self._state = .ready
    }

    /// Lazily opens the database/store rooted at the results path. Safe to call repeatedly.
    private func configureStoreIfNeeded(baseUrl: URL) -> ResultStore? {
        syncQueue.sync(flags: .barrier) {
            if let store { return store }
            do {
                let database = try Database(baseUrl: baseUrl)
                let store = ResultStore(database: database)
                let blobStore = BlobStore(baseUrl: baseUrl, database: database)
                self.database = database
                self.store = store
                self.blobStore = blobStore
                self.backgroundIngest = BackgroundIngest(store: store, blobStore: blobStore)
                self.baseUrl = baseUrl
                return store
            } catch {
                os_log("Failed opening database at '%@': %@", log: .default, type: .error, baseUrl.path, "\(error)")
                return nil
            }
        }
    }

    private var resultStore: ResultStore? {
        syncQueue.sync { store }
    }

    var sharedBlobStore: BlobStore? {
        syncQueue.sync { blobStore }
    }

    /// The (at most `limit`) most recent runs containing a test with the given route identifier,
    /// newest first. Indexed lookup — does not scan the whole corpus.
    func resultBundles(containingRouteIdentifier routeIdentifier: String, limit: Int) -> [ResultBundle] {
        resultStore?.resultBundles(containingRouteIdentifier: routeIdentifier, limit: limit) ?? []
    }

    /// Lightweight per-run summaries (newest first) for the results-list endpoints. Reads only
    /// `result_bundle` rollup columns — no test rows, no `ResultBundle.make`.
    func resultSummaries() -> [ResultStore.ResultSummary] {
        resultStore?.resultSummaries() ?? []
    }

    func allTargets() -> [String] {
        resultStore?.allTargets() ?? []
    }

    func allDevices(in target: String) -> [Device] {
        let devices = resultStore?.devices(inTarget: target) ?? []
        return Array(Set(devices.map { Device(model: $0.model, os: $0.os) })).sorted(by: { $0.description < $1.description })
    }

    func pendingResultBundles(baseUrl: URL, depth: Int, mergeResults: Bool) -> [PendingResultBundle] {
        let store = configureStoreIfNeeded(baseUrl: baseUrl)

        let benchId = benchmarkStart()
        let bundleUrls = findResultBundles(at: baseUrl, depth: depth, mergeResults: mergeResults)
        os_log("Found %ld test bundles searching '%@' with depth %ld in %fms", log: .default, type: .info, bundleUrls.count, baseUrl.absoluteString, depth, benchmarkStop(benchId))

        var results = [(result: PendingResultBundle, creationDate: Date)]()

        let queue = OperationQueue()
        let localSyncQueue = DispatchQueue(label: "com.subito.cachi.pending.result.bundles")

        for urls in bundleUrls {
            queue.addOperation {
                let bundlePath = (urls.count > 1 ? urls.first?.deletingLastPathComponent() : urls.first)?.path ?? ""

                let benchId = benchmarkStart()
                let creationDate = ((try? FileManager.default.attributesOfItem(atPath: bundlePath))?[.creationDate] as? Date) ?? Date()

                if let identifier = store?.runIdentifier(forSourceUrls: urls) {
                    os_log("Restored partial result bundle '%@' from db in %fms", log: .default, type: .info, bundlePath, benchmarkStop(benchId))
                    let result = (result: PendingResultBundle(identifier: identifier, resultUrls: urls), creationDate: creationDate)
                    localSyncQueue.sync { results.append(result) }
                } else {
                    let parser = Parser()
                    if let pendingResultBundle = parser.parsePendingResultBundle(urls: urls) {
                        let result = (result: pendingResultBundle, creationDate: creationDate)
                        localSyncQueue.sync { results.append(result) }
                    }
                    os_log("Parsed partial result bundle '%@' in %fms", log: .default, type: .info, bundlePath, benchmarkStop(benchId))
                }
            }
        }

        queue.waitUntilAllOperationsAreFinished()

        return results.sorted(by: { $0.creationDate > $1.creationDate }).map(\.result)
    }

    func parse(baseUrl: URL, depth: Int, mergeResults: Bool) {
        guard let store = configureStoreIfNeeded(baseUrl: baseUrl) else { return }

        syncQueue.sync(flags: .barrier) { _state = .parsing(progress: 0) }

        var benchId = benchmarkStart()
        var bundleUrls = findResultBundles(at: baseUrl, depth: depth, mergeResults: mergeResults)
        os_log("Found %ld test bundles searching '%@' with depth %ld in %fms", log: .default, type: .info, bundleUrls.count, baseUrl.absoluteString, depth, benchmarkStop(benchId))

        // Skip bundles already ingested into the database.
        bundleUrls = bundleUrls.filter { store.runIdentifier(forSourceUrls: $0) == nil }

        let parser = Parser()
        benchId = benchmarkStart()
        for (index, urls) in bundleUrls.enumerated() {
            autoreleasepool {
                if let resultBundle = parser.parseResultBundles(urls: urls) {
                    store.upsert(resultBundle)
                    syncQueue.sync(flags: .barrier) {
                        _state = .parsing(progress: Double(index) / Double(bundleUrls.count))
                    }
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        // This can be done asynchronously as it doesn't contain data that is immediately needed
                        try? parser.splitHtmlCoverageFile(resultBundle: resultBundle)
                        try? parser.generagePerFolderLineCoverage(resultBundle: resultBundle, destinationUrl: resultBundle.codeCoveragePerFolderJsonUrl)
                        // Cache the coverage-presence flag so the results list never probes the
                        // filesystem per request (it's resolved once here, after generation).
                        let hasCoverage = resultBundle.codeCoveragePerFolderJsonUrl
                            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                        self?.resultStore?.setHasCoverage(identifier: resultBundle.identifier, hasCoverage: hasCoverage)
                    }
                }
            }
        }
        os_log("Parsed %ld test bundles in %fms", log: .default, type: .info, bundleUrls.count, benchmarkStop(benchId))

        syncQueue.sync(flags: .barrier) { _state = .ready }

        // Cheap DB hygiene after a parse pass.
        syncQueue.sync { database }?.performMaintenance()

        // Deferred, low-priority: extract failure detail + materialize video/log blobs. Off the
        // parse critical path so a failure flood grows a backlog rather than blocking. Once blobs
        // are fully materialized, enforce the optional disk-size cap (evict whole runs oldest-first).
        syncQueue.sync { backgroundIngest }?.runAsync { [weak self] in
            guard let self, let maxBytes = maxDiskSizeBytes else { return }
            syncQueue.sync { self.blobStore }?.enforceDiskLimit(maxBytes: maxBytes)
        }
    }

    func result(identifier: String) -> ResultBundle? {
        resultStore?.resultBundle(identifier: identifier)
    }

    func test(summaryIdentifier: String) -> ResultBundle.Test? {
        resultStore?.test(summaryIdentifier: summaryIdentifier)
    }

    /// A test plus its owning run, by summary identifier. Indexed lookup (no corpus scan); used by
    /// the test-detail and session-log HTML pages that need the run for `userInfo`/navigation.
    func testWithResultBundle(summaryIdentifier: String) -> (test: ResultBundle.Test, resultBundle: ResultBundle)? {
        resultStore?.testWithResultBundle(summaryIdentifier: summaryIdentifier)
    }

    func testActionSummary(test: ResultBundle.Test?) -> ActionTestSummary? {
        guard let test, let summaryIdentifier = test.summaryIdentifier else { return nil }

        // Read-through: rebuild from SQLite if detail was extracted; else read live from the bundle.
        if let stored = resultStore?.reconstructTestSummary(summaryIdentifier: summaryIdentifier) {
            return stored
        }

        let cachi = CachiKit(url: test.xcresultUrl)
        return try? cachi.actionTestSummary(identifier: summaryIdentifier)
    }

    func testActionActivitySummaries(summaryIdentifier: String) -> [ActionTestActivitySummary]? {
        guard let test = test(summaryIdentifier: summaryIdentifier) else {
            return nil
        }

        return testActionActivitySummaries(test: test)
    }

    func testActionActivitySummaries(test: ResultBundle.Test?) -> [ActionTestActivitySummary]? {
        testActionSummary(test: test)?.activitySummaries
    }

    /// Resolves a serve-ready base video for an attachment to a local file at `destinationUrl`.
    ///
    /// Prefers the **original high-quality** recording exported straight from the `.xcresult`, so the
    /// step-by-step playback stays sharp. Only when the bundle is no longer on disk (e.g. pruned)
    /// does it fall back to the stored transcoded blob, which is intentionally smaller and lower
    /// quality. The blob itself is materialized off the request path by `BackgroundIngest` after each
    /// parse, so the fallback is available once the xcresult is gone. Returns false if neither source
    /// can produce a video.
    func materializeVideo(test: ResultBundle.Test, attachmentIdentifier: String, destinationUrl: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationUrl.path) { return true }
        try? fileManager.createDirectory(at: destinationUrl.deletingLastPathComponent(), withIntermediateDirectories: true)

        // 1. Preferred: export the original high-quality video directly from the xcresult.
        let cachi = CachiKit(url: test.xcresultUrl)
        do {
            try cachi.export(identifier: attachmentIdentifier, destinationPath: destinationUrl.path)
            if fileManager.fileExists(atPath: destinationUrl.path) {
                return true
            }
        } catch {
            try? fileManager.removeItem(at: destinationUrl)
        }

        // 2. Fallback: the stored transcoded blob (lower quality, but survives xcresult pruning).
        if let summaryIdentifier = test.summaryIdentifier,
           let blobStore = sharedBlobStore,
           let hash = resultStore?.videoBlobHash(summaryIdentifier: summaryIdentifier) {
            let blobUrl = blobStore.url(forHash: hash)
            if (try? fileManager.copyItem(at: blobUrl, to: destinationUrl)) != nil {
                return true
            }
        }

        return false
    }

    func testSessionLogs(diagnosticsIdentifier: String) -> ResultBundle.Test.SessionLogs? {
        guard let store = resultStore, let test = store.test(diagnosticsIdentifier: diagnosticsIdentifier) else {
            return nil
        }

        // Read-through: serve from the blob store if the channels were already materialized.
        if let blobStore = sharedBlobStore {
            let app = storedSessionLog(diagnosticsIdentifier: diagnosticsIdentifier, kind: "app", store: store, blobStore: blobStore)
            let runner = storedSessionLog(diagnosticsIdentifier: diagnosticsIdentifier, kind: "runner", store: store, blobStore: blobStore)
            let session = storedSessionLog(diagnosticsIdentifier: diagnosticsIdentifier, kind: "session", store: store, blobStore: blobStore)
            if app != nil || runner != nil || session != nil {
                return .init(appStandardOutput: app, runerAppStandardOutput: runner, sessionLogs: session)
            }
        }

        // Miss: extract live from the xcresult now (and store for next time if possible).
        let cachi = CachiKit(url: test.xcresultUrl)
        guard let sessionLogs = try? cachi.actionInvocationSessionLogs(identifier: diagnosticsIdentifier, sessionLogs: .all) else {
            return nil
        }

        if let blobStore = sharedBlobStore, let rowId = store.testRowId(summaryIdentifier: test.summaryIdentifier ?? "") {
            persistSessionLogs(sessionLogs, testRowId: rowId, store: store, blobStore: blobStore)
        }

        return .init(appStandardOutput: sessionLogs[.appStdOutErr], runerAppStandardOutput: sessionLogs[.runnerAppStdOutErr], sessionLogs: sessionLogs[.session])
    }

    private func storedSessionLog(diagnosticsIdentifier: String, kind: String, store: ResultStore, blobStore: BlobStore) -> String? {
        guard let hash = store.sessionLogBlobHash(diagnosticsIdentifier: diagnosticsIdentifier, kind: kind),
              let gzipped = try? Data(contentsOf: blobStore.url(forHash: hash)),
              let data = gzipped.cachiGunzipped()
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func persistSessionLogs(_ logs: [CachiKit.SessionLogs: String], testRowId: Int, store: ResultStore, blobStore: BlobStore) {
        let mapping: [(CachiKit.SessionLogs, String)] = [(.appStdOutErr, "app"), (.runnerAppStdOutErr, "runner"), (.session, "session"), (.scheduling, "scheduling")]
        let pending = Dictionary(uniqueKeysWithValues: store.sessionLogsNeedingBlob(testRowId: testRowId).map { ($0.kind, $0.logId) })
        for (key, kind) in mapping {
            guard let logId = pending[kind], let text = logs[key], !text.isEmpty,
                  let gzipped = Data(text.utf8).cachiGzipped(),
                  let hash = try? blobStore.store(gzipped, kind: .sessionLog)
            else {
                continue
            }
            store.setSessionLogBlobHash(logId: logId, hash: hash)
        }
    }

    func resultsTestStats(target: String, device: Device, type: ResultBundle.TestStatsType, windowSize: Int?) -> [ResultBundle.TestStats] {
        class RawTestStats: NSObject {
            var groupName: String
            var testName: String
            var firstSummaryIdentifier: String
            var executionSequence = [Bool]()
            var successCount = 0
            var failureCount = 0
            var successDuration: Double = 0
            var failureDuration: Double = 0
            var minSuccessDuration: Double = .greatestFiniteMagnitude
            var maxSuccessDuration: Double = 0
            var minFailureDuration: Double = .greatestFiniteMagnitude
            var maxFailureDuration: Double = 0

            init(groupName: String, testName: String, firstSummaryIdentifier: String) {
                self.groupName = groupName
                self.testName = testName
                self.firstSummaryIdentifier = firstSummaryIdentifier
            }
        }

        let windowSize = windowSize ?? Self.defaultStatWindowSize
        let deviceTests = resultStore?.statsTests(target: target, deviceModel: device.model, deviceOs: device.os) ?? []

        let stats = NSMutableDictionary()

        for test in deviceTests {
            guard let testSummaryIdentifier = test.summaryIdentifier else { continue }

            if stats[test.targetIdentifier] == nil {
                stats[test.targetIdentifier] = RawTestStats(groupName: test.groupName, testName: test.name, firstSummaryIdentifier: testSummaryIdentifier)
            }
            let testStat = stats[test.targetIdentifier] as! RawTestStats

            if testStat.executionSequence.count >= windowSize {
                continue
            }

            if test.status == .success {
                testStat.executionSequence.append(true)
                testStat.successCount += 1
                testStat.successDuration += test.duration
                testStat.minSuccessDuration = min(testStat.minSuccessDuration, test.duration)
                testStat.maxSuccessDuration = max(testStat.maxSuccessDuration, test.duration)
            } else {
                testStat.executionSequence.append(false)
                testStat.failureCount += 1
                testStat.failureDuration += test.duration
                testStat.minFailureDuration = min(testStat.minFailureDuration, test.duration)
                testStat.maxFailureDuration = max(testStat.maxFailureDuration, test.duration)
            }
        }

        var result = [ResultBundle.TestStats]()
        for stat in stats.allValues as! [RawTestStats] {
            let elementWeight = 1.0 / Double(stat.executionSequence.count)
            var totalWeight = 0.0
            var failureRatio = 0.0
            for (index, success) in stat.executionSequence.enumerated() {
                let weight = elementWeight * (1.0 - Double(index) / Double(windowSize))
                totalWeight += weight

                if !success {
                    failureRatio += weight
                }
            }

            let successRatio = 1.0 - failureRatio / totalWeight

            let averageDuration = Double(stat.successDuration + stat.failureDuration) / Double(stat.successCount + stat.failureCount)
            let resultStat = ResultBundle.TestStats(first_summary_identifier: stat.firstSummaryIdentifier,
                                                    group_name: stat.groupName,
                                                    test_name: stat.testName,
                                                    average_s: averageDuration,
                                                    success_min_s: stat.minSuccessDuration == .greatestFiniteMagnitude ? 0 : stat.minSuccessDuration,
                                                    success_max_s: stat.maxSuccessDuration,
                                                    success_count: stat.successCount,
                                                    failure_min_s: stat.minFailureDuration,
                                                    failure_max_s: stat.maxFailureDuration,
                                                    failure_count: stat.failureCount,
                                                    success_ratio: successRatio,
                                                    execution_sequence: stat.executionSequence.map { $0 ? "S" : "F" }.joined())
            result.append(resultStat)
        }

        switch type {
        case .flaky:
            return result.sorted(by: { $0.success_ratio < $1.success_ratio })
        case .slowest:
            return result.sorted(by: { $0.average_s > $1.average_s })
        case .fastest:
            return result.sorted(by: { $0.average_s < $1.average_s })
        case .slowestFlaky:
            return result.sorted(by: { ($0.success_max_s + $0.failure_max_s) * (1.0 + Double($0.failure_count)) > ($1.success_max_s + $1.failure_max_s) * (1.0 + Double($1.failure_count)) })
        }
    }

    func testStats(summaryIdentifier: String) -> ResultBundle.Test.Stats? {
        guard let test = test(summaryIdentifier: summaryIdentifier) else {
            return nil
        }

        return testStats(md5Identifier: test.routeIdentifier)
    }

    func testStats(md5Identifier: String) -> ResultBundle.Test.Stats {
        // Newest-first, capped: the route index serves the order + limit directly.
        let matchingTests = resultStore?.tests(routeIdentifier: md5Identifier, limit: 51) ?? []

        let successfulTests = matchingTests.filter { $0.status == .success }
        let failedTests = matchingTests.filter { $0.status == .failure }

        let averageSuccessfulTests = successfulTests.prefix(3)
        let averageFailedTests = failedTests.prefix(3)

        let successfulCount = Double(averageSuccessfulTests.count)
        let failureCount = Double(averageFailedTests.count)

        var successTotal: Double?
        if successfulCount > 0 {
            successTotal = averageSuccessfulTests.reduce(0) { $0 + $1.duration }
        }

        var failureTotal: Double?
        if failureCount > 0 {
            failureTotal = averageFailedTests.reduce(0) { $0 + $1.duration }
        }

        var executionAverage = 1.0
        if successfulCount + failureCount > 0 {
            let failedWeight = 0.5
            executionAverage = ((successTotal ?? 0.0) + failedWeight * (failureTotal ?? 0.0)) / (successfulCount + failedWeight * failureCount)
        }

        var successAverage: Double?
        if successTotal != nil {
            successAverage = successTotal! / successfulCount
        }
        var failureAverage: Double?
        if failureTotal != nil {
            failureAverage = failureTotal! / failureCount
        }

        let allTests = (successfulTests + failedTests).sorted { $0.testStartDate > $1.testStartDate }

        let groupNames = Set(allTests.map(\.groupName))
        let testNames = Set(allTests.map(\.name))
        let deviceModels = Set(allTests.map(\.deviceModel))
        let deviceOses = Set(allTests.map(\.deviceOs))

        guard groupNames.count == 1, testNames.count == 1, deviceModels.count == 1, deviceOses.count == 1 else {
            return ResultBundle.Test.Stats(group_name: "",
                                           test_name: "",
                                           device_model: "",
                                           device_os: "",
                                           average_s: -1,
                                           success_average_s: -1,
                                           failure_average_s: -1,
                                           success_count: 0,
                                           failure_count: 0,
                                           tests: [])
        }

        return ResultBundle.Test.Stats(group_name: groupNames.first!,
                                       test_name: testNames.first!,
                                       device_model: deviceModels.first!,
                                       device_os: deviceOses.first!,
                                       average_s: executionAverage,
                                       success_average_s: successAverage,
                                       failure_average_s: failureAverage,
                                       success_count: successfulTests.count,
                                       failure_count: failedTests.count,
                                       tests: allTests)
    }

    private func findResultBundles(at url: URL, depth: Int, mergeResults: Bool) -> [[URL]] {
        guard depth > 0 else { return [] }

        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants, .skipsHiddenFiles]

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: options, errorHandler: nil) else { return [] }

        var testBundleUrls = [URL]()
        for case let item as NSURL in enumerator {
            guard let resourceValues = try? item.resourceValues(forKeys: resourceKeys),
                  let isDirectory = resourceValues[.isDirectoryKey] as? Bool,
                  let name = resourceValues[.nameKey] as? String
            else {
                continue
            }

            if isDirectory {
                if name == Cachi.dataFolderName {
                    enumerator.skipDescendants()
                } else if name.hasSuffix(".xcresult") {
                    testBundleUrls.append(item as URL)
                    enumerator.skipDescendants()
                } else if enumerator.level >= depth {
                    enumerator.skipDescendants()
                }
            }
        }

        var groupedUrls: [[URL]]
        if mergeResults {
            let groupDictionary = Dictionary(grouping: testBundleUrls, by: { $0.deletingLastPathComponent() })
            groupedUrls = Array(groupDictionary.values)
        } else {
            groupedUrls = testBundleUrls.map { [$0] }
        }

        return groupedUrls
    }
}
