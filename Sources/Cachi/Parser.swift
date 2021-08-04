import Foundation
import CachiKit
import os

class Parser {
    private let actionInvocationRecordCache = NSCache<NSURL, ActionsInvocationRecord>()
    
    func parsePendingResultBundle(urls: [URL]) -> PendingResultBundle? {
        let benchId = benchmarkStart()
        let bundlePath = (urls.count > 1 ? urls.first?.deletingLastPathComponent() : urls.first)?.absoluteString ?? ""
        defer { os_log("Parsing partial data in test bundle '%@' in %fms", log: .default, type: .info, bundlePath, benchmarkStop(benchId)) }

        guard let bundleIdentifier = bundleIdentifier(urls: urls) else {
            os_log("Failed extracting bundle identigier at '%@'", log: .default, type: .info, bundlePath)
            return nil
        }
        
        return PendingResultBundle(identifier: bundleIdentifier, resultUrls: urls)
    }
    
    func parseResultBundles(urls: [URL]) -> ResultBundle? {
        let benchId = benchmarkStart()
        
        let bundlePath = (urls.count > 1 ? urls.first?.deletingLastPathComponent() : urls.first)?.absoluteString ?? ""
        defer { os_log("Parsed test bundle '%@' in %fms", log: .default, type: .info, bundlePath, benchmarkStop(benchId)) }
        
        guard let bundleIdentifier = bundleIdentifier(urls: urls) else {
            os_log("Failed extracting bundle identigier at '%@'", log: .default, type: .info, bundlePath)
            return nil
        }

        var tests = [ResultBundle.Test]()

        var userInfo: ResultBundle.UserInfo?
        var runDestinations = Set<String>()
        var testsCrashCount = 0
        
        let urlQueue = OperationQueue()
        let testQueue = OperationQueue()
        let syncQueue = DispatchQueue(label: "com.subito.cachi.parsing")
        
        for url in urls {
            urlQueue.addOperation { [unowned self] in
                let cachi = CachiKit(url: url)
                guard let invocationRecord = actionInvocationRecordCache.object(forKey: url as NSURL) ?? (try? cachi.actionsInvocationRecord()) else {
                    os_log("Failed parsing actionsInvocationRecord", log: .default, type: .info)
                    return
                }
                actionInvocationRecordCache.setObject(invocationRecord, forKey: url as NSURL)
                                
                for action in invocationRecord.actions {
                    testQueue.addOperation { [unowned self] in
                        guard let testRef = action.actionResult.testsRef else {
                            return
                        }
                    
                        guard let testPlanSummaries = (try? cachi.actionTestPlanRunSummaries(identifier: testRef.id))?.summaries else {
                            return
                        }
                    
                        guard testPlanSummaries.count == 1 else {
                            os_log("Unexpected multiple test plan summaries '%@'", log: .default, type: .info, url.absoluteString)
                            return
                        }
                        
                        let extractedTests = self.extractTests(resultBundleUrl: url, actionTestableSummaries: testPlanSummaries.first?.testableSummaries, actionRecord: action)
                        let targetDevice = action.runDestination.targetDeviceRecord
                        let testDestination = "\(targetDevice.modelName) (\(targetDevice.operatingSystemVersion))"
                        
                        syncQueue.sync {
                            tests += extractedTests
                            runDestinations.insert(testDestination)
                        }
                    }
                }
                                
                let invocationRecordCrashCount = optimisticCrashCount(in: invocationRecord)
                let resultBundleUserInfo = resultBundleUserInfoPlist(in: url)

                syncQueue.sync {
                    testsCrashCount += invocationRecordCrashCount
                    userInfo = userInfo ?? resultBundleUserInfo
                }
            }
        }
        
        urlQueue.waitUntilAllOperationsAreFinished()
        testQueue.waitUntilAllOperationsAreFinished()

        guard tests.count > 0 else {
            os_log("No tests found in test bundle '%@'", log: .default, type: .info, bundlePath)
            return nil
        }

        let date = tests.map { $0.startDate }.sorted().first!
        let totalExecutionTime = tests.reduce(0, { $0 + $1.duration })
        
        let testsPassed = tests.filter { $0.status == .success }
        let testsFailed = tests.filter { $0.status == .failure }
        let testsGrouped = Array(Dictionary(grouping: tests, by: { "\($0.groupName)-\($0.name)-\($0.deviceModel)-\($0.deviceOs)" }).values)
        let testsRepeated = testsGrouped.filter { $0.count > 1 }
        let testsPassedRetring = testsRepeated.compactMap { $0.first(where: { $0.status == .success }) }
        let testsFailedRetring = testsGrouped.filter { $0.contains(where: { $0.status == .success })}.flatMap { $0 }.filter { $0.status == .failure }
        let testsUniquelyFailed = testsGrouped.filter { $0.allSatisfy({ $0.status == .failure })}.compactMap { $0.first }
                
        return ResultBundle(identifier: bundleIdentifier,
                            xcresultUrls: Set(urls),
                            destinations: runDestinations.joined(separator: ", "),
                            date: date,
                            totalExecutionTime: totalExecutionTime,
                            tests: tests,
                            testsPassed: testsPassed,
                            testsFailed: testsFailed,
                            testsPassedRetring: testsPassedRetring,
                            testsFailedRetring: testsFailedRetring,
                            testsUniquelyFailed: testsUniquelyFailed,
                            testsRepeated: testsRepeated,
                            testsCrashCount: testsCrashCount,
                            userInfo: userInfo)
    }
    
    private func bundleIdentifier(urls: [URL]) -> String? {
        guard let url = urls.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else {
            os_log("No urls passed", log: .default, type: .info)
            return nil
        }
                
        let cachi = CachiKit(url: url)
        guard let invocationRecord = actionInvocationRecordCache.object(forKey: url as NSURL) ?? (try? cachi.actionsInvocationRecord()) else {
            os_log("Failed parsing actionsInvocationRecord", log: .default, type: .info)
            return nil
        }
        actionInvocationRecordCache.setObject(invocationRecord, forKey: url as NSURL)
        
        guard let metadataIdentifier = invocationRecord.metadataRef?.id,
              let metaData = try? cachi.actionsInvocationMetadata(identifier: metadataIdentifier) else {
            os_log("Failed parsing actionsInvocationMetadata", log: .default, type: .info)
            return nil
        }
        
        return metaData.uniqueIdentifier
    }
    
    private func crashCount(_ cachi: CachiKit, in tests: [ResultBundle.Test], at url: URL) -> Int {
        var crashedTestsCount = 0
        for (index, test) in tests.enumerated() {
            guard test.status == .failure else { continue }

            os_log("Processing test %ld/%ld", log: .default, type: .info, index + 1, tests.count)
            autoreleasepool {
                let testSummary = try? cachi.actionTestSummary(identifier: test.summaryIdentifier!)

                let actions = testSummary?.activitySummaries.flatten()
                if actions?.contains(where: { $0.title?.contains(" crashed in ") == true }) == true {
                    crashedTestsCount += 1
                }
            }
        }
        
        return crashedTestsCount
    }
    
    private func optimisticCrashCount(in actionsInvocationRecord: ActionsInvocationRecord) -> Int {
        let messages = actionsInvocationRecord.issues?.testFailureSummaries?.map({ $0.message }) ?? []
        
        return messages.filter({ $0.contains(" crashed in ") }).count
    }
    
    private func extractTests(resultBundleUrl: URL, actionTestSummariesGroup: [ActionTestSummaryGroup], actionRecord: ActionRecord, targetName: String?) -> [ResultBundle.Test] {
        var result = [ResultBundle.Test]()
    
        for group in actionTestSummariesGroup {
            if let tests = group.subtests as? [ActionTestMetadata] {
                result += tests.compactMap {
                    guard let testStatus = ResultBundle.Test.Status(rawValue: $0.testStatus.lowercased()) else {
                        os_log("Unsupported test status %@ found in test %@", log: .default, type: .info, $0.testStatus, $0.name)
                        return nil
                    }
                    
                    let targetDeviceRecord = actionRecord.runDestination.targetDeviceRecord
                    let testIdentifier = $0.identifier.md5Value

                    let routeIdentifier = [targetName ?? "", group.name, $0.name, targetDeviceRecord.modelName, targetDeviceRecord.operatingSystemVersion].joined(separator: "-").md5Value
                    
                    guard let summaryIdentifier = $0.summaryRef?.id else {
                        return nil
                    }
                    
                    return ResultBundle.Test(xcresultUrl: resultBundleUrl,
                                             identifier: testIdentifier,
                                             routeIdentifier: routeIdentifier,
                                             url: "\(TestRoute().path)?\(summaryIdentifier)",
                                             targetName: targetName ?? "",
                                             groupName: group.name,
                                             groupIdentifier: group.identifier,
                                             name: $0.name,
                                             startDate: actionRecord.startedTime,
                                             duration: $0.duration ?? 0,
                                             status: testStatus,
                                             deviceName: targetDeviceRecord.name,
                                             deviceModel: targetDeviceRecord.modelName,
                                             deviceOs: targetDeviceRecord.operatingSystemVersion,
                                             deviceIdentifier: targetDeviceRecord.identifier,
                                             diagnosticsIdentifier: actionRecord.actionResult.diagnosticsRef?.id,
                                             summaryIdentifier: summaryIdentifier,
                                             externalCoverage: nil)
                }
            } else if let subGroups =  group.subtests as? [ActionTestSummaryGroup] {
                result += extractTests(resultBundleUrl: resultBundleUrl, actionTestSummariesGroup: subGroups, actionRecord: actionRecord, targetName: targetName)
            } else {
                os_log("Unsupported groups %@", log: .default, type: .info, String(describing: type(of: group.subtests)))
            }
        }
    
        return result
    }
    
    private func extractTests(resultBundleUrl: URL, actionTestableSummaries: [ActionTestableSummary]?, actionRecord: ActionRecord) -> [ResultBundle.Test] {
        guard let actionTestableSummaries = actionTestableSummaries else { return [] }
    
        return actionTestableSummaries.flatMap { extractTests(resultBundleUrl: resultBundleUrl, actionTestSummariesGroup: $0.tests, actionRecord: actionRecord, targetName: $0.targetName) }
    }
    
    private func resultBundleUserInfoPlist(in resultBundleUrl: URL) -> ResultBundle.UserInfo? {
        guard let data = try? Data(contentsOf: resultBundleUrl.appendingPathComponent("Info.plist")) else { return nil }
        
        return try? PropertyListDecoder().decode(ResultBundle.UserInfo.self, from: data)
    }        
}
