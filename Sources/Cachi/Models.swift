import Foundation

struct PendingResultBundle: Codable {
    let identifier: String
    let resultBundleUrl: URL
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
        let branchName: String
        let commitMessage: String
        let commitHash: String
    }
    
    let identifier: String
    let destinations: String
    let resultBundleUrl: URL
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
