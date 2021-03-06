import Foundation
import CachiKit
import os

class State {
    static let shared = State()
    
    private var _resultBundles: [ResultBundle]
    var resultBundles: [ResultBundle] {
        return syncQueue.sync { _resultBundles }
    }
    
    enum Status { case ready, parsing(progress: Double) }
    private var _state: Status
    var state: Status {
        return syncQueue.sync { _state }
    }
    
    private let syncQueue = DispatchQueue(label: String(describing: State.self), attributes: .concurrent)
    private let operationQueue = OperationQueue()
    
    init() {
        self._resultBundles = []
        self._state = .ready
    }
    
    func reset() {
        syncQueue.sync(flags: .barrier) {
            _resultBundles = []
            _state = .ready
        }
    }
    
    func partialResultBundles(baseUrl: URL, depth: Int) -> [PartialResultBundle] {
        let benchId = benchmarkStart()
        let bundleUrls = findResultBundles(at: baseUrl, depth: depth)
        os_log("Found %ld test bundles searching '%@' with depth %ld in %fms", log: .default, type: .info, bundleUrls.count, baseUrl.absoluteString, depth, benchmarkStop(benchId))
        
        var results = [(result: PartialResultBundle, creationDate: Date)]()
               
        for bundleUrl in bundleUrls {
            let benchId = benchmarkStart()
            let creationDate = ((try? FileManager.default.attributesOfItem(atPath: bundleUrl.path))?[.creationDate] as? Date) ?? Date()
            
            if let cachedResultBundle = cachedResultBundle(for: bundleUrl) {
                os_log("Restored partial result bundle '%@' from cache in %fms", log: .default, type: .info, bundleUrl.absoluteString, benchmarkStop(benchId))
                results.append((result: PartialResultBundle(identifier: cachedResultBundle.identifier, resultBundleUrl: cachedResultBundle.resultBundleUrl), creationDate: creationDate))
            } else {
                let parser = Parser()
                if let partialResultBundle = parser.parsePartialResultBundle(at: bundleUrl) {
                    results.append((result: partialResultBundle, creationDate: creationDate))
                }
                os_log("Parsed partial result bundle '%@' in %fms", log: .default, type: .info, bundleUrl.absoluteString, benchmarkStop(benchId))
            }
        }

        return results.sorted(by: { $0.creationDate > $1.creationDate }).map { $0.result }
    }
    
    func parse(baseUrl: URL, depth: Int) {
        syncQueue.sync(flags: .barrier) { _state = .parsing(progress: 0) }
        
        let benchId = benchmarkStart()
        var bundleUrls = findResultBundles(at: baseUrl, depth: depth)
        os_log("Found %ld test bundles searching '%@' with depth %ld in %fms", log: .default, type: .info, bundleUrls.count, baseUrl.absoluteString, depth, benchmarkStop(benchId))
  
        var resultBundles = [ResultBundle]()
        for (index, bundleUrl) in bundleUrls.enumerated().reversed() {
            guard !self.resultBundles.contains(where: { $0.resultBundleUrl == bundleUrl }) else {
                os_log("Already parsed, skipping test bundle '%@'", log: .default, type: .info)
                bundleUrls.remove(at: index)
                continue
            }
            
            let benchId = benchmarkStart()
            if let cachedResultBundle = cachedResultBundle(for: bundleUrl) {
                os_log("Restored test bundle '%@' from cache in %fms", log: .default, type: .info, bundleUrl.absoluteString, benchmarkStop(benchId))
                resultBundles.append(cachedResultBundle)
                bundleUrls.remove(at: index)
            }
        }
        
        syncQueue.sync(flags: .barrier) {
            _resultBundles += resultBundles
            _resultBundles.sort(by: { $0.date > $1.date })
        }
        
        if bundleUrls.count > 0 {
            let parser = Parser()
            let benchId = benchmarkStart()
            for (index, bundleUrl) in bundleUrls.enumerated() {
                autoreleasepool {
                    if let resultBundle = parser.parseResultBundle(at: bundleUrl)  {
                        syncQueue.sync(flags: .barrier) {
                            _resultBundles.append(resultBundle)
                            _resultBundles.sort(by: { $0.date > $1.date })
                            _state = .parsing(progress: Double(index) / Double(bundleUrls.count))
                            writeCachedResultBundle(resultBundle)
                        }
                    }
                }
            }
            os_log("Parsed %ld test bundles in %fms", log: .default, type: .info, bundleUrls.count, benchmarkStop(benchId))
        }
        
        syncQueue.sync(flags: .barrier) { _state = .ready }
    }
    
    func result(identifier: String) -> ResultBundle? {
        return resultBundles.first { $0.identifier == identifier }
    }
    
    func test(summaryIdentifier: String) -> ResultBundle.Test? {
        return resultBundles.flatMap { $0.tests }.first { $0.summaryIdentifier == summaryIdentifier }
    }
    
    func testActionSummaries(summaryIdentifier: String) -> [ActionTestActivitySummary]? {
        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.summaryIdentifier == summaryIdentifier })}) else {
            return nil
        }
        
        guard let test = resultBundle.tests.first(where: { $0.summaryIdentifier == summaryIdentifier }) else {
            return nil
        }
                
        let cachi = CachiKit(url: resultBundle.resultBundleUrl)
        let testSummary = try? cachi.actionTestSummary(identifier: test.summaryIdentifier!)
        
        return testSummary?.activitySummaries
    }
    
    func testSessionLogs(diagnosticsIdentifier: String) -> ResultBundle.Test.SessionLogs? {
        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.diagnosticsIdentifier == diagnosticsIdentifier })}) else {
            return nil
        }
        
        let cachi = CachiKit(url: resultBundle.resultBundleUrl)
        let sessionLogs = try? cachi.actionInvocationSessionLogs(identifier: diagnosticsIdentifier, sessionLogs: .all)
        
        return .init(appStandardOutput: sessionLogs?[.appStdOutErr], runerAppStandardOutput: sessionLogs?[.runnerAppStdOutErr], sessionLogs: sessionLogs?[.session])
    }

    func testStats(md5Identifier: String) -> ResultBundle.Test.Stats {
        var successfulTests = ArraySlice<ResultBundle.Test>()
        var failedTests = ArraySlice<ResultBundle.Test>()
        
        let sortedResultBundles = resultBundles.sorted { $0.date > $1.date }
                
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
            successTotal = successfulTests.reduce(0, { $0 + $1.duration })
        }
        
        var failureTotal: Double?
        if failureCount > 0 {
            failureTotal = failedTests.reduce(0, { $0 + $1.duration })
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
        
        let groupNames = Set(allTests.map { $0.groupName })
        let testNames = Set(allTests.map { $0.name })
        let deviceModels = Set(allTests.map { $0.deviceModel })
        let deviceOses = Set(allTests.map { $0.deviceOs })
                
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
        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.identifier == test.identifier })}),
              let test = resultBundle.tests.first(where: { $0.identifier == test.identifier }) else {
            return
        }

        let cachi = CachiKit(url: resultBundle.resultBundleUrl)
        
        let actions = cachedActions ?? State.shared.testActionSummaries(summaryIdentifier: test.summaryIdentifier!) ?? []
        
        let filemanager = FileManager.default
        
        let destinationUrl = Cachi.temporaryFolderUrl.appendingPathComponent(test.identifier)
        try? filemanager.createDirectory(at: destinationUrl, withIntermediateDirectories: true, attributes: nil)
        
        for attachment in actions.flatten().flatMap({ $0.attachments }) {
            guard let filename = attachment.filename,
                  let attachmentIdentifier = attachment.payloadRef?.id else {
                continue
            }
            
            let attachmentDestinationPath = destinationUrl.appendingPathComponent(filename).path
            guard filemanager.fileExists(atPath: attachmentDestinationPath) == false else { continue }
            
            try? cachi.export(identifier: attachmentIdentifier, destinationPath: attachmentDestinationPath)
        }
    }
    
    private func writeCachedResultBundle(_ bundle: ResultBundle) {
        guard let data = try? JSONEncoder().encode(bundle) else { return }
        
        try? data.write(to: makeCacheUrl(for: bundle.resultBundleUrl))
    }
    
    private func cachedResultBundle(for bundleUrl: URL) -> ResultBundle? {
        guard let data = try? Foundation.Data(contentsOf: makeCacheUrl(for: bundleUrl)) else { return nil }
        
        return try? JSONDecoder().decode(ResultBundle.self, from: data)
    }
    
    private func makeCacheUrl(for bundleUrl: URL) -> URL {
        let url = bundleUrl.appendingPathComponent(Cachi.cacheFolderName)
        
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
        return url.appendingPathComponent("cached_result.json")
    }
    
    private func findResultBundles(at url: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [] }
        
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants, .skipsHiddenFiles]

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: options, errorHandler: nil) else { return [] }

        var testBundleUrls = [URL]()
        for case let item as NSURL in enumerator {
            guard let resourceValues = try? item.resourceValues(forKeys: resourceKeys),
                  let isDirectory = resourceValues[.isDirectoryKey] as? Bool,
                  let name = resourceValues[.nameKey] as? String else {
                continue
            }
            
            if isDirectory {
                if name.hasSuffix(".xcresult") {
                    testBundleUrls.append(item as URL)
                } else if enumerator.level >= depth {
                    enumerator.skipDescendants()
                }
            }
        }
        
        return testBundleUrls
    }
}
