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

    private var _resultBundles: [ResultBundle]
    var resultBundles: [ResultBundle] {
        syncQueue.sync { _resultBundles }
    }

    enum Status { case ready, parsing(progress: Double) }
    private var _state: Status
    var state: Status {
        syncQueue.sync { _state }
    }

    private let syncQueue = DispatchQueue(label: String(describing: State.self), attributes: .concurrent)
    private let operationQueue = OperationQueue()

    init() {
        _resultBundles = []
        _state = .ready
    }

    func reset() {
        syncQueue.sync(flags: .barrier) {
            _resultBundles = []
            _state = .ready
        }
    }

    func allTargets() -> [String] {
        let tests = resultBundles.flatMap(\.tests)
        let targets = tests.map(\.targetName)

        return Array(Set(targets)).sorted()
    }

    func allDevices(in target: String) -> [Device] {
        let targetTests = allTests(in: target)
        let targetDevices = targetTests.map { Device(model: $0.deviceModel, os: $0.deviceOs) }

        return Array(Set(targetDevices)).sorted(by: { $0.description < $1.description })
    }

    func allTests(in target: String) -> [ResultBundle.Test] {
        let tests = resultBundles.flatMap(\.tests)
        return tests.filter { $0.targetName == target }
    }

    func pendingResultBundles(baseUrl: URL, depth: Int, mergeResults: Bool) -> [PendingResultBundle] {
        let benchId = benchmarkStart()
        let bundleUrls = findResultBundles(at: baseUrl, depth: depth, mergeResults: mergeResults)
        os_log("Found %ld test bundles searching '%@' with depth %ld in %fms", log: .default, type: .info, bundleUrls.count, baseUrl.absoluteString, depth, benchmarkStop(benchId))

        var results = [(result: PendingResultBundle, creationDate: Date)]()

        let queue = OperationQueue()
        let syncQueue = DispatchQueue(label: "com.subito.cachi.pending.result.bundles")

        for urls in bundleUrls {
            queue.addOperation { [unowned self] in
                let bundlePath = (urls.count > 1 ? urls.first?.deletingLastPathComponent() : urls.first)?.path ?? ""

                let benchId = benchmarkStart()
                let creationDate = ((try? FileManager.default.attributesOfItem(atPath: bundlePath))?[.creationDate] as? Date) ?? Date()

                if let cachedResultBundle = cachedResultBundle(urls: urls) {
                    os_log("Restored partial result bundle '%@' from cache in %fms", log: .default, type: .info, bundlePath, benchmarkStop(benchId))
                    let result = (result: PendingResultBundle(identifier: cachedResultBundle.identifier, resultUrls: urls), creationDate: creationDate)
                    syncQueue.sync { results.append(result) }
                } else {
                    let parser = Parser()
                    if let pendingResultBundle = parser.parsePendingResultBundle(urls: urls) {
                        let result = (result: pendingResultBundle, creationDate: creationDate)
                        syncQueue.sync { results.append(result) }
                    }
                    os_log("Parsed partial result bundle '%@' in %fms", log: .default, type: .info, bundlePath, benchmarkStop(benchId))
                }
            }
        }

        queue.waitUntilAllOperationsAreFinished()

        return results.sorted(by: { $0.creationDate > $1.creationDate }).map(\.result)
    }

    func parse(baseUrl: URL, depth: Int, mergeResults: Bool) {
        syncQueue.sync(flags: .barrier) { _state = .parsing(progress: 0) }

        var benchId = benchmarkStart()
        var bundleUrls = findResultBundles(at: baseUrl, depth: depth, mergeResults: mergeResults)
        os_log("Found %ld test bundles searching '%@' with depth %ld in %fms", log: .default, type: .info, bundleUrls.count, baseUrl.absoluteString, depth, benchmarkStop(benchId))

        let queue = OperationQueue()
        let syncQueue = DispatchQueue(label: "com.subito.cachi.pending.result.bundles")

        var resultBundles = [ResultBundle]()
        var parsedIndexes = [Int]()
        for (index, urls) in bundleUrls.enumerated() {
            queue.addOperation { [unowned self] in
                let bundlePath = (urls.count > 1 ? urls.first?.deletingLastPathComponent() : urls.first)?.absoluteString ?? ""

                guard !self.resultBundles.contains(where: { $0.xcresultUrls == Set(urls) }) else {
                    os_log("Already parsed, skipping test bundle '%@'", log: .default, type: .info, bundlePath)
                    return syncQueue.sync { parsedIndexes.append(index) }
                }

                let benchId = benchmarkStart()
                if let cachedResultBundle = cachedResultBundle(urls: urls) {
                    os_log("Restored test bundle '%@' from cache in %fms", log: .default, type: .info, bundlePath, benchmarkStop(benchId))
                    syncQueue.sync {
                        resultBundles.append(cachedResultBundle)
                        parsedIndexes.append(index)
                    }
                }
            }
        }

        queue.waitUntilAllOperationsAreFinished()

        parsedIndexes.sorted().reversed().forEach { bundleUrls.remove(at: $0) }

        syncQueue.sync(flags: .barrier) {
            _resultBundles += resultBundles
            _resultBundles.sort(by: { $0.testStartDate > $1.testStartDate })
        }

        let parser = Parser()
        benchId = benchmarkStart()
        for (index, urls) in bundleUrls.enumerated() {
            autoreleasepool {
                if let resultBundle = parser.parseResultBundles(urls: urls) {
                    syncQueue.sync(flags: .barrier) {
                        _resultBundles.append(resultBundle)
                        _resultBundles.sort(by: { $0.testStartDate > $1.testStartDate })
                        _state = .parsing(progress: Double(index) / Double(bundleUrls.count))
                        writeCachedResultBundle(resultBundle)
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        // This can be done asynchronously as it doesn't contain data that is immediately needed
                        try? parser.splitHtmlCoverageFile(resultBundle: resultBundle)
                        try? parser.generagePerFolderLineCoverage(resultBundle: resultBundle, destinationUrl: resultBundle.codeCoveragePerFolderJsonUrl)
                    }
                }
            }
        }
        os_log("Parsed %ld test bundles in %fms", log: .default, type: .info, bundleUrls.count, benchmarkStop(benchId))

        syncQueue.sync(flags: .barrier) { _state = .ready }
    }

    func result(identifier: String) -> ResultBundle? {
        resultBundles.first { $0.identifier == identifier }
    }

    func test(summaryIdentifier: String) -> ResultBundle.Test? {
        resultBundles.flatMap(\.tests).first { $0.summaryIdentifier == summaryIdentifier }
    }
    
    func testActionSummary(test: ResultBundle.Test?) -> ActionTestSummary? {
        guard let test, let summaryIdentifier = test.summaryIdentifier else { return nil }

        let cachi = CachiKit(url: test.xcresultUrl)
        let testSummary = try? cachi.actionTestSummary(identifier: summaryIdentifier)

        return testSummary
    }

    func testActionActivitySummaries(summaryIdentifier: String) -> [ActionTestActivitySummary]? {
        guard let test = test(summaryIdentifier: summaryIdentifier) else {
            return nil
        }

        return testActionActivitySummaries(test: test)
    }

    func testActionActivitySummaries(test: ResultBundle.Test?) -> [ActionTestActivitySummary]? {
        guard let test, let summaryIdentifier = test.summaryIdentifier else { return nil }

        let cachi = CachiKit(url: test.xcresultUrl)
        let testSummary = try? cachi.actionTestSummary(identifier: summaryIdentifier)

        return testSummary?.activitySummaries
    }

    func testSessionLogs(diagnosticsIdentifier: String) -> ResultBundle.Test.SessionLogs? {
        guard let test = resultBundles.flatMap(\.tests).first(where: { $0.diagnosticsIdentifier == diagnosticsIdentifier }) else {
            return nil
        }

        let cachi = CachiKit(url: test.xcresultUrl)
        let sessionLogs = try? cachi.actionInvocationSessionLogs(identifier: diagnosticsIdentifier, sessionLogs: .all)

        return .init(appStandardOutput: sessionLogs?[.appStdOutErr], runerAppStandardOutput: sessionLogs?[.runnerAppStdOutErr], sessionLogs: sessionLogs?[.session])
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

            init(groupName: String, testName: String, firstSummaryIdentifier: String) {
                self.groupName = groupName
                self.testName = testName
                self.firstSummaryIdentifier = firstSummaryIdentifier
            }
        }

        let windowSize = windowSize ?? Self.defaultStatWindowSize
        let targetTests = allTests(in: target).sorted(by: { $0.testStartDate > $1.testStartDate }).filter { $0.groupName != "System Failures" }
        let deviceTests = targetTests.filter { $0.deviceModel == device.model && $0.deviceOs == device.os }

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
                                                    success_ratio: successRatio,
                                                    success_count: stat.successCount,
                                                    failure_count: stat.failureCount,
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
            return result.sorted(by: { $0.average_s / pow($0.success_ratio + Double.leastNonzeroMagnitude, 2.0) > $1.average_s / pow($1.success_ratio + Double.leastNonzeroMagnitude, 2.0) })
        }
    }

    func testStats(md5Identifier: String) -> ResultBundle.Test.Stats {
        var successfulTests = ArraySlice<ResultBundle.Test>()
        var failedTests = ArraySlice<ResultBundle.Test>()

        let sortedResultBundles = resultBundles.sorted { $0.testStartDate > $1.testStartDate }

        for resultBundle in sortedResultBundles {
            let matchingTests = resultBundle.tests.filter { $0.routeIdentifier == md5Identifier }

            successfulTests += matchingTests.filter { $0.status == .success }
            failedTests += matchingTests.filter { $0.status == .failure }

            if successfulTests.count + failedTests.count > 10 {
                break
            }
        }

        successfulTests = successfulTests.prefix(3)
        failedTests = failedTests.prefix(3)

        let successfulCount = Double(successfulTests.count)
        let failureCount = Double(failedTests.count)

        var successTotal: Double?
        if successfulCount > 0 {
            successTotal = successfulTests.reduce(0) { $0 + $1.duration }
        }

        var failureTotal: Double?
        if failureCount > 0 {
            failureTotal = failedTests.reduce(0) { $0 + $1.duration }
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

        let allTests = successfulTests + failedTests

        let groupNames = Set(allTests.map(\.groupName))
        let testNames = Set(allTests.map(\.name))
        let deviceModels = Set(allTests.map(\.deviceModel))
        let deviceOses = Set(allTests.map(\.deviceOs))

        guard groupNames.count == 1, testNames.count == 1, deviceModels.count == 1, deviceModels.count == 1 else {
            return ResultBundle.Test.Stats(group_name: "",
                                           test_name: "",
                                           device_model: "",
                                           device_os: "",
                                           average_s: -1,
                                           success_average_s: -1,
                                           failure_average_s: -1,
                                           success_count: 0,
                                           failure_count: 0)
        }

        return ResultBundle.Test.Stats(group_name: groupNames.first!,
                                       test_name: testNames.first!,
                                       device_model: deviceModels.first!,
                                       device_os: deviceOses.first!,
                                       average_s: executionAverage,
                                       success_average_s: successAverage,
                                       failure_average_s: failureAverage,
                                       success_count: Int(successfulCount),
                                       failure_count: Int(failureCount))
    }

    func dumpAttachments(in test: ResultBundle.Test, cachedActions: [ActionTestActivitySummary]?) {
        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.identifier == test.identifier }) }),
              let test = resultBundle.tests.first(where: { $0.identifier == test.identifier })
        else {
            return
        }

        let cachi = CachiKit(url: test.xcresultUrl)

        let actions = cachedActions ?? State.shared.testActionActivitySummaries(test: test) ?? []

        let filemanager = FileManager.default

        let destinationUrl = Cachi.temporaryFolderUrl.appendingPathComponent(test.identifier)
        try? filemanager.createDirectory(at: destinationUrl, withIntermediateDirectories: true, attributes: nil)

        for attachment in actions.flatten().flatMap(\.attachments) {
            guard let filename = attachment.filename,
                  let attachmentIdentifier = attachment.payloadRef?.id
            else {
                continue
            }

            let attachmentDestinationPath = destinationUrl.appendingPathComponent(filename).path
            guard filemanager.fileExists(atPath: attachmentDestinationPath) == false else { continue }

            try? cachi.export(identifier: attachmentIdentifier, destinationPath: attachmentDestinationPath)
        }
    }

    private func writeCachedResultBundle(_ bundle: ResultBundle) {
        guard let data = try? JSONEncoder().encode(bundle) else { return }

        let baseUrl: URL

        if bundle.xcresultUrls.count == 0 {
            return
        } else if bundle.xcresultUrls.count == 1 {
            baseUrl = Array(bundle.xcresultUrls)[0]
        } else {
            baseUrl = Array(bundle.xcresultUrls)[0].deletingLastPathComponent()
        }

        let cacheUrl = makeCacheUrl(baseUrl: baseUrl).appendingPathComponent("cached_result.json")
        try? data.write(to: cacheUrl)
    }

    private func cachedResultBundle(urls: [URL]) -> ResultBundle? {
        let baseUrl: URL

        if urls.count == 0 {
            return nil
        } else if urls.count == 1 {
            baseUrl = urls[0]
        } else {
            baseUrl = urls[0].deletingLastPathComponent()
        }

        let cacheUrl = makeCacheUrl(baseUrl: baseUrl).appendingPathComponent("cached_result.json")
        guard let data = try? Foundation.Data(contentsOf: cacheUrl) else { return nil }

        if let cache = try? ZippyJSONDecoder().decode(ResultBundle.self, from: data) {
            for url in cache.xcresultUrls {
                if !urls.contains(url) {
                    return nil
                }
            }

            return cache
        }

        return nil
    }

    private func makeCacheUrl(baseUrl: URL) -> URL {
        let url = baseUrl.appendingPathComponent(Cachi.cacheFolderName)

        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
        return url
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
                if name.hasSuffix(".xcresult") {
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
