import Foundation
import CachiKit

extension ResultBundle.Test {
    func failureMessage() -> String? {
        guard let summaries = State.shared.testActionSummaries(test: self) else {
            return nil
        }
        
        var activities = [ActionTestActivitySummary]()
        for summary in summaries {
            activities.append(contentsOf: summary.flattenActivitySummaries())
        }
                
        let errorActivities = activities.filter { $0.activityType == "com.apple.dt.xctest.activity-type.testAssertionFailure" }
        
        return errorActivities.last?.title
    }
}

extension Collection where Element == ResultBundle.Test {
    func failureMessages() -> [String: String] {
        let syncQueue = DispatchQueue(label: "com.subito.cachi.failureMessages")
        var ret = [String: String]()
        let queue = OperationQueue()
        
        for test in self where test.status == .failure {
            queue.addOperation {
                if let failureMessage = test.failureMessage() {
                    syncQueue.sync { ret[test.identifier] = failureMessage }
                }
            }
        }

        queue.waitUntilAllOperationsAreFinished()
        return ret
    }

}

private extension ActionTestActivitySummary {
    func flattenActivitySummaries() -> [ActionTestActivitySummary] {
        var result = [ActionTestActivitySummary]()
        
        result.append(self)
        let subactivities = subactivities.flatMap { $0.flattenActivitySummaries() }
        result.append(contentsOf: subactivities)
        
        return result
    }
}

