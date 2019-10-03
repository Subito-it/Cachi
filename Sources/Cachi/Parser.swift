import Foundation
import CachiKit
import os

class Parser {
    func parseResultBundle(at url: URL) -> ResultBundle? {
        let benchId = benchmarkStart()
        defer { os_log("Parsed test bundle '%@' in %fms", log: .default, type: .info, url.absoluteString, benchmarkStop(benchId)) }

        var tests = [ResultBundle.Test]()
                
        let cachi = CachiKit(url: url)
        guard let invocationRecord = try? cachi.actionsInvocationRecord() else {
            os_log("Failed parsing actionsInvocationRecord", log: .default, type: .info)
            return nil
        }
        guard let metadataIdentifier = invocationRecord.metadataRef?.id,
              let metaData = try? cachi.actionsInvocationMetadata(identifier: metadataIdentifier) else {
            os_log("Failed parsing actionsInvocationMetadata", log: .default, type: .info)
            return nil
        }
        
        let bundleIdentifier = metaData.uniqueIdentifier
        
        var runDestinations = Set<String>()
        
        for action in invocationRecord.actions {
            guard let testRef = action.actionResult.testsRef else {
                continue
            }
        
            guard let testPlanSummaries = (try? cachi.actionTestPlanRunSummaries(identifier: testRef.id))?.summaries else {
                continue
            }
        
            guard testPlanSummaries.count == 1 else {
                os_log("Unexpected multiple test plan summaries '%@'", log: .default, type: .info, url.absoluteString)
                continue
            }
            tests += extractTests(actionTestableSummaries: testPlanSummaries.first?.testableSummaries, actionRecord: action)
            
            let targetDevice = action.runDestination.targetDeviceRecord
            runDestinations.insert("\(targetDevice.modelName) (\(targetDevice.operatingSystemVersion))" )
        }
                
        guard tests.count > 0 else {
            os_log("No tests found in test bundle '%@'", log: .default, type: .info, url.absoluteString)
            return nil
        }

        let date = tests.map { $0.startDate }.sorted().first!
        let totalExecutionTime = tests.reduce(0, { $0 + $1.duration })
        
        let testsCrashCount = optimisticCrashCount(in: invocationRecord)

        let userInfo = userInfoPlist(resultBundleUrl: url)
        
        let testsPassed = tests.filter { $0.status == .success }
        let testsFailed = tests.filter { $0.status == .failure }
        let testsGrouped = Array(Dictionary(grouping: tests, by: { "\($0.groupName)-\($0.name)-\($0.deviceModel)-\($0.deviceOs)" }).values)
        let testsRepeated = testsGrouped.filter { $0.count > 1 }
        let testsPassedRetring = testsRepeated.compactMap { $0.first(where: { $0.status == .success }) }
        let testsFailedRetring = testsGrouped.filter { $0.contains(where: { $0.status == .success })}.flatMap { $0 }.filter { $0.status == .failure }
        let testsUniquelyFailed = testsGrouped.filter { $0.allSatisfy({ $0.status == .failure })}.compactMap { $0.first }
        
        return ResultBundle(identifier: bundleIdentifier,
                            destinations: runDestinations.joined(separator: ", "),
                            resultBundleUrl: url,
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
    
    private func extractTests(actionTestSummariesGroup: [ActionTestSummaryGroup], actionRecord: ActionRecord, targetName: String?) -> [ResultBundle.Test] {
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
                    
                    return ResultBundle.Test(identifier: testIdentifier,
                                             url: "\(TestRoute().path)?\(testIdentifier)",
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
                                             summaryIdentifier: $0.summaryRef?.id)
                }
            } else if let subGroups =  group.subtests as? [ActionTestSummaryGroup] {
                result += extractTests(actionTestSummariesGroup: subGroups, actionRecord: actionRecord, targetName: targetName)
            } else {
                os_log("Unsupported groups %@", log: .default, type: .info, String(describing: type(of: group.subtests)))
            }
        }
    
        return result
    }
    
    private func extractTests(actionTestableSummaries: [ActionTestableSummary]?, actionRecord: ActionRecord) -> [ResultBundle.Test] {
        guard let actionTestableSummaries = actionTestableSummaries else { return [] }
    
        return actionTestableSummaries.flatMap { extractTests(actionTestSummariesGroup: $0.tests, actionRecord: actionRecord, targetName: $0.targetName) }
    }
    
    private func userInfoPlist(resultBundleUrl: URL) -> ResultBundle.UserInfo? {
        guard let data = try? Data(contentsOf: resultBundleUrl.appendingPathComponent("Info.plist")) else { return nil }
        
        return try? PropertyListDecoder().decode(ResultBundle.UserInfo.self, from: data)
    }        
}
