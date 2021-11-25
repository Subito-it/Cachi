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
        let first_summary_identifier: String
        let group_name: String
        let test_name: String
        let average_s: TimeInterval
        let success_min_s: Double
        let success_max_s: Double
        let success_ratio: Double
        let success_count: Int
        let failure_count: Int
        let execution_sequence: String
    }
    
    struct Test: Codable, Hashable {
        struct SessionLogs: Codable {
            let appStandardOutput: String?
            let runerAppStandardOutput: String?
            let sessionLogs: String?
        }

        struct Stats: Codable {
            let group_name: String
            let test_name: String
            let device_model: String
            let device_os: String
            let average_s: Double
            let success_average_s: Double?
            let failure_average_s: Double?
            let success_count: Int
            let failure_count: Int
        }

        enum Status: String, Codable {
            case success, failure
        }
        
        let xcresultUrl: URL
        let identifier: String
        let routeIdentifier: String
        let url: String
        let targetName: String
        let groupName: String
        let groupIdentifier: String
        let name: String
        let startDate: Date
        let duration: Double
        let status: Status
        let deviceName: String
        let deviceModel: String
        let deviceOs: String
        let deviceIdentifier: String
        let diagnosticsIdentifier: String?
        let summaryIdentifier: String?
    }
    
    struct UserInfo: Codable {
        enum Error: Swift.Error { case empty }
        
        let branchName: String?
        let commitMessage: String?
        let commitHash: String?
        let metadata: String?
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
            self.commitMessage = try container.decodeIfPresent(String.self, forKey: .commitMessage)
            self.commitHash = try container.decodeIfPresent(String.self, forKey: .commitHash)
            self.metadata = try container.decodeIfPresent(String.self, forKey: .metadata)

            if self.branchName == nil, self.commitMessage == nil, self.commitHash == nil, self.metadata == nil {
                throw Error.empty
            }
        }
    }
    
    let identifier: String
    let xcresultUrls: Set<URL>
    let destinations: String
    let date: Date
    let totalExecutionTime: TimeInterval
    let tests: [Test]
    let testsPassed: [Test]
    let testsFailed: [Test]
    let testsPassedRetring: [Test]
    let testsFailedRetring: [Test]
    let testsUniquelyFailed: [Test]
    let testsRepeated: [[Test]]
    let testsCrashCount: Int
    let userInfo: UserInfo?
}

extension ResultBundle.Test {
    func matches(_ test: ResultBundle.Test) -> Bool {
        return
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
