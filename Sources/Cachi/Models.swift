import Foundation

struct PendingResultBundle: Codable {
    let identifier: String
    let resultUrls: [URL]
}

struct ResultBundle: Codable {
    enum TestStatsType: String, Codable {
        case flaky
        case slowest
        case fastest
        case slowestFlaky = "slowest_flaky"
    }

    struct TestStats: Codable, Hashable {
        var first_summary_identifier: String
        var group_name: String
        var test_name: String
        var average_s: TimeInterval
        var success_min_s: Double
        var success_max_s: Double
        var success_ratio: Double
        var success_count: Int
        var failure_count: Int
        var execution_sequence: String
    }

    struct Test: Codable, Hashable {
        struct SessionLogs: Codable {
            var appStandardOutput: String?
            var runerAppStandardOutput: String?
            var sessionLogs: String?
        }

        struct Stats: Codable {
            var group_name: String
            var test_name: String
            var device_model: String
            var device_os: String
            var average_s: Double
            var success_average_s: Double?
            var failure_average_s: Double?
            var success_count: Int
            var failure_count: Int
        }

        enum Status: String, Codable {
            case success, failure
        }

        var xcresultUrl: URL
        var identifier: String
        var routeIdentifier: String
        var url: String
        var targetName: String
        var groupName: String
        var groupIdentifier: String
        var name: String
        var testStartDate: Date
        var duration: Double
        var status: Status
        var deviceName: String
        var deviceModel: String
        var deviceOs: String
        var deviceIdentifier: String
        var diagnosticsIdentifier: String?
        var summaryIdentifier: String?
    }

    struct UserInfo: Codable {
        enum Error: Swift.Error { case empty }

        var branchName: String?
        var commitMessage: String?
        var commitHash: String?
        var metadata: String?
        var sourceBasePath: String?
        var githubBaseUrl: String?
        var startDate: Date?
        var endDate: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.branchName = try container.decodeIfPresent(String.self, forKey: .branchName)

            self.commitMessage = try container.decodeIfPresent(String.self, forKey: .commitMessage)
            self.commitHash = try container.decodeIfPresent(String.self, forKey: .commitHash)
            self.metadata = try container.decodeIfPresent(String.self, forKey: .metadata)

            self.sourceBasePath = try container.decodeIfPresent(String.self, forKey: .sourceBasePath)
            self.githubBaseUrl = try container.decodeIfPresent(String.self, forKey: .githubBaseUrl)

            self.startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
            self.endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)


            if branchName == nil,
               commitMessage == nil,
               commitHash == nil,
               metadata == nil,
               startDate == nil,
               endDate == nil,
               sourceBasePath == nil,
               githubBaseUrl == nil,
                throw Error.empty
            }
        }
    }

    var identifier: String
    var xcresultUrls: Set<URL>
    var destinations: String
    var testStartDate: Date
    var testEndDate: Date
    var totalExecutionTime: TimeInterval
    var tests: [Test]
    var testsPassed: [Test]
    var testsFailed: [Test]
    var testsFailedBySystem: [Test]
    var testsPassedRetring: [Test]
    var testsFailedRetring: [Test]
    var testsUniquelyFailed: [Test]
    var testsRepeated: [[Test]]
    var testsCrashCount: Int
    var userInfo: UserInfo?
}

extension ResultBundle.Test {
    func matches(_ test: ResultBundle.Test) -> Bool {
        deviceModel == test.deviceModel &&
            deviceOs == test.deviceOs &&
            groupName == test.groupName &&
            name == test.name
    }
}

// This needs to be a class to optimize per folder coverage extraction
class Coverage: Codable {
    class Item: Codable {
        class File: Codable, Hashable {
            class Summary: Codable, Hashable {
                class Detail: Codable, Hashable {
                    let count: Int
                    let covered: Int
                    let percent: Double

                    static func == (lhs: Coverage.Item.File.Summary.Detail, rhs: Coverage.Item.File.Summary.Detail) -> Bool {
                        lhs.count == rhs.count && lhs.covered == rhs.covered && lhs.percent == rhs.percent
                    }

                    func hash(into hasher: inout Hasher) {
                        hasher.combine(count)
                        hasher.combine(covered)
                        hasher.combine(percent)
                    }
                }

                let functions: Detail
                let instantiations: Detail
                let lines: Detail

                static func == (lhs: Coverage.Item.File.Summary, rhs: Coverage.Item.File.Summary) -> Bool {
                    lhs.functions == rhs.functions && lhs.instantiations == rhs.instantiations && lhs.lines == rhs.lines
                }

                func hash(into hasher: inout Hasher) {
                    hasher.combine(functions)
                    hasher.combine(instantiations)
                    hasher.combine(lines)
                }
            }

            let filename: String
            let summary: Summary

            static func == (lhs: Coverage.Item.File, rhs: Coverage.Item.File) -> Bool {
                lhs.filename == rhs.filename && lhs.summary == rhs.summary
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(filename)
                hasher.combine(summary)
            }
        }

        let files: [File]
    }

    let data: [Item]
}

struct PathCoverage: Codable {
    let path: String
    let percent: Double
}

extension ResultBundle {
    var codeCoverageSplittedHtmlBaseUrl: URL? {
        xcresultUrls.first?.deletingLastPathComponent().appendingPathComponent(Cachi.cacheFolderName).appendingPathComponent("coverage")
    }

    var codeCoverageBaseUrl: URL? {
        xcresultUrls.first?.deletingLastPathComponent()
    }

    var codeCoverageJsonUrl: URL? {
        codeCoverageBaseUrl?.appendingPathComponent("coverage.json")
    }

    var codeCoverageJsonSummaryUrl: URL? {
        codeCoverageBaseUrl?.appendingPathComponent("coverage-summary.json")
    }

    var codeCoverageHtmlUrl: URL? {
        codeCoverageBaseUrl?.appendingPathComponent("coverage.html")
    }

    var codeCoveragePerFolderJsonUrl: URL? {
        codeCoverageBaseUrl?.appendingPathComponent("coverage-folders.json")
    }
}

extension ResultBundle.Test {
    func with(groupName: String, groupIdentifier: String, name: String) -> Self {
        var me = self
        me.groupName = groupName
        me.groupIdentifier = groupIdentifier
        me.name = name

        return me
    }
}
