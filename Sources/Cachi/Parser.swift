import CachiKit
import Foundation
import os
import ZippyJSON

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

        var runDestinations = Set<String>()
        var testsCrashCount = 0

        let urlQueue = OperationQueue()
        let testQueue = OperationQueue()
        let syncQueue = DispatchQueue(label: "com.subito.cachi.parsing")

        let userInfo = urls.lazy.compactMap { self.resultBundleUserInfoPlist(in: $0) }.first

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

                        var extractedTests = extractTests(resultBundleUrl: url, actionTestableSummaries: testPlanSummaries.first?.testableSummaries, actionRecord: action)
                        let targetDevice = action.runDestination.targetDeviceRecord
                        let testDestination = "\(targetDevice.modelName) (\(targetDevice.operatingSystemVersion))"
                        extractedTests = resolveSystemFailedTestNames(extractedTests, userInfo: userInfo)

                        syncQueue.sync {
                            tests += extractedTests
                            runDestinations.insert(testDestination)
                        }
                    }
                }

                let invocationRecordCrashCount = optimisticCrashCount(in: invocationRecord)

                syncQueue.sync {
                    testsCrashCount += invocationRecordCrashCount
                }
            }
        }

        urlQueue.waitUntilAllOperationsAreFinished()
        testQueue.waitUntilAllOperationsAreFinished()

        guard tests.count > 0 else {
            os_log("No tests found in test bundle '%@'", log: .default, type: .info, bundlePath)
            return nil
        }

        let totalExecutionTime = tests.reduce(0.0) { $0 + $1.duration }

        return ResultBundle.make(identifier: bundleIdentifier,
                                 xcresultUrls: Set(urls),
                                 destinations: runDestinations.joined(separator: ", "),
                                 totalExecutionTime: totalExecutionTime,
                                 tests: tests,
                                 testsCrashCount: testsCrashCount,
                                 userInfo: userInfo)
    }

    func splitHtmlCoverageFile(resultBundle: ResultBundle) throws {
        guard let coverageUrl = resultBundle.codeCoverageHtmlUrl,
              let coverageSplittedUrl = resultBundle.codeCoverageSplittedHtmlBaseUrl else { return }

        let benchId = benchmarkStart()
        defer { os_log("Splitted coverage files for '%@' in %fms", log: .default, type: .info, coverageUrl.absoluteString, benchmarkStop(benchId)) }

        try FileManager.default.createDirectory(at: coverageSplittedUrl, withIntermediateDirectories: false, attributes: nil)

        let splitter = CodeCoverageHtmlSplitter(url: coverageUrl)
        try splitter.split(destinationUrl: coverageSplittedUrl, basePath: "")
    }

    func generagePerFolderLineCoverage(resultBundle: ResultBundle, destinationUrl: URL?) throws {
        guard let destinationUrl else { return }

        let benchId = benchmarkStart()
        defer { os_log("Per folder coverage generation for '%@' in %fms", log: .default, type: .info, destinationUrl.absoluteString, benchmarkStop(benchId)) }

        let coverage = try extractPerFolderLineCoverage(resultBundle: resultBundle)

        let data = try JSONEncoder().encode(coverage)
        try data.write(to: destinationUrl)
    }

    private func extractPerFolderLineCoverage(resultBundle: ResultBundle) throws -> [PathCoverage] {
        guard let coverageUrl = resultBundle.codeCoverageJsonSummaryUrl else { return [] }

        let coverage = try ZippyJSONDecoder().decode(Coverage.self, from: Data(contentsOf: coverageUrl))
        let files = coverage.data.first?.files ?? []

        var folderCoverageAggregation = [String: Set<Coverage.Item.File>]()
        for file in files {
            let pathComponents = file.filename.components(separatedBy: "/").dropLast()

            var cumulatedPath = ""
            for pathComponent in pathComponents {
                cumulatedPath += pathComponent + "/"
                var set = folderCoverageAggregation[cumulatedPath, default: Set<Coverage.Item.File>()]
                set.insert(file)
                folderCoverageAggregation[cumulatedPath] = set
            }
        }

        var folderCoverage = [PathCoverage]()
        for (path, coverages) in folderCoverageAggregation {
            let totalLines = coverages.reduce(0) { $0 + $1.summary.lines.count }
            guard totalLines > 0 else { continue }

            let coveredLines = coverages.reduce(0) { $0 + $1.summary.lines.covered }
            let percent = Double(coveredLines) / Double(totalLines)

            folderCoverage.append(PathCoverage(path: path, percent: percent * 100))
        }

        return folderCoverage.sorted(by: { $0.path < $1.path }).filter { $0.path != "/" }
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
              let metaData = try? cachi.actionsInvocationMetadata(identifier: metadataIdentifier)
        else {
            os_log("Failed parsing actionsInvocationMetadata", log: .default, type: .info)
            return nil
        }

        return metaData.uniqueIdentifier
    }

    private func optimisticCrashCount(in actionsInvocationRecord: ActionsInvocationRecord) -> Int {
        // To properly extract crash count we would need to extract the test summary which does however take too long
        let messages = actionsInvocationRecord.issues?.testFailureSummaries?.map(\.message) ?? []

        return messages.filter { $0.contains(" crashed in ") }.count
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
                                             url: "\(TestRoute.path)?\(summaryIdentifier)",
                                             html_url: "\(TestRouteHTML.path)?id=\(summaryIdentifier)",
                                             targetName: targetName ?? "",
                                             groupName: group.name,
                                             groupIdentifier: group.identifier,
                                             name: $0.name,
                                             testStartDate: actionRecord.startedTime,
                                             duration: $0.duration ?? 0,
                                             status: testStatus,
                                             deviceName: targetDeviceRecord.name,
                                             deviceModel: targetDeviceRecord.modelName,
                                             deviceOs: targetDeviceRecord.operatingSystemVersion,
                                             deviceIdentifier: targetDeviceRecord.identifier,
                                             diagnosticsIdentifier: actionRecord.actionResult.diagnosticsRef?.id,
                                             summaryIdentifier: summaryIdentifier)
                }
            } else if let subGroups = group.subtests as? [ActionTestSummaryGroup] {
                result += extractTests(resultBundleUrl: resultBundleUrl, actionTestSummariesGroup: subGroups, actionRecord: actionRecord, targetName: targetName)
            } else {
                os_log("Unsupported groups %@", log: .default, type: .info, String(describing: type(of: group.subtests)))
            }
        }

        return result
    }

    private func extractTests(resultBundleUrl: URL, actionTestableSummaries: [ActionTestableSummary]?, actionRecord: ActionRecord) -> [ResultBundle.Test] {
        guard let actionTestableSummaries else { return [] }

        return actionTestableSummaries.flatMap { extractTests(resultBundleUrl: resultBundleUrl, actionTestSummariesGroup: $0.tests, actionRecord: actionRecord, targetName: $0.targetName) }
    }

    private func resultBundleUserInfoPlist(in resultBundleUrl: URL) -> ResultBundle.UserInfo? {
        guard let data = try? Data(contentsOf: resultBundleUrl.appendingPathComponent("Info.plist")) else { return nil }

        return try? PropertyListDecoder().decode(ResultBundle.UserInfo.self, from: data)
    }

    private func resolveSystemFailedTestNames(_ tests: [ResultBundle.Test], userInfo: ResultBundle.UserInfo?) -> [ResultBundle.Test] {
        guard let userInfo else { return tests }

        var updatedTests = [ResultBundle.Test]()

        for test in tests {
            if test.groupName == "System Failures",
               let components = userInfo.xcresultPathToFailedTestName?[test.xcresultUrl.lastPathComponent]?.components(separatedBy: "/"),
               components.count == 2 {
                let suiteName = components[0]
                let testName = components[1] + "()"
                updatedTests.append(test.with(groupName: suiteName, groupIdentifier: suiteName, name: testName)) // groupName and groupIdentifier are expected to match
            } else {
                updatedTests.append(test)
            }
        }

        return updatedTests
    }
}
