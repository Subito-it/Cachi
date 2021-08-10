import Foundation

struct PendingResultBundle: Codable {
    let identifier: String
    let resultUrls: [URL]
}

struct ResultBundle: Codable {
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
        let externalCoverage: ExternalCoverage?
    }
    
    struct UserInfo: Codable {
        let branchName: String
        let commitMessage: String
        let commitHash: String
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

extension ResultBundle {
    // This model is used to extract coverage data from manually generated using llvm-cov
    // An example of the expected format can be found here: https://github.com/Subito-it/Mendoza/blob/cbf6b8298dc2c80e4b634a3368db56afba93be72/Sources/Mendoza/Operations/CodeCoverageCollectionOperation.swift#L77
    struct ExternalCoverage: Codable, Hashable {
        struct Totals: Codable, Hashable {
            let lines: Coverage
            let functions: Coverage
            let instantiations: Coverage
        }
        
        struct Coverage: Codable, Hashable {
            let count: Int
            let covered: Int
            let percentage: Double
        }
        
        struct Regions: Codable, Hashable {
            let count: Int
            let covered: Int
            let percentage: Double
        }
        
        let totals: Totals
        let regions: Regions
        let files: [String]
    }
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
        codeCoverageBaseUrl?.appendingPathComponent("coverage-folder.json")
    }
}
