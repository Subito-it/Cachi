extension ResultBundle {
    func htmlTitle() -> String {
        if let branchName = userInfo?.branchName, let commitHash = userInfo?.commitHash {
            return "\(branchName) - \(commitHash)"
        } else {
            return identifier
        }
    }
    
    func htmlSubtitle() -> String {
        return userInfo?.commitMessage ?? ""
    }
}

extension ResultBundle {
    func htmlStatusImageUrl(for test: ResultBundle.Test) -> String {
        if test.status == .success {
            return "/image?imageTestPass"
        }
        
        if testsUniquelyFailed.contains(where: { $0.matches(test) }) || test.groupName == "System Failures" {
            return "/image?imageTestFail"
        } else {
            return "/image?imageTestRetried"
        }
    }
    
    func htmlStatusTitle(for test: ResultBundle.Test) -> String {
        if test.status == .success {
            return "Passed"
        }
        
        if testsUniquelyFailed.contains(where: { $0.matches(test) }) || test.groupName == "System Failures" {
            return "Failed"
        } else {
            return "Failed, but passed on retry"
        }
    }
    
    func htmlTextColor(for test: ResultBundle.Test) -> String {
        if test.status == .success {
            return "color-text"
        }
        
        if testsUniquelyFailed.contains(where: { $0.matches(test) }) || test.groupName == "System Failures" {
            return "color-error"
        } else {
            return "color-retry"
        }
    }
}

extension ResultBundle {
    func htmlStatusImageUrl(includeSystemFailures: Bool) -> String {
        var failedTestCount = testsUniquelyFailed.count
        
        if includeSystemFailures {
            failedTestCount += testsFailedBySystem.count
        }
        
        if failedTestCount > 0 {
            return "/image?imageTestFail"
        } else {
            return "/image?imageTestPass"
        }
    }
    
    func htmlStatusTitle() -> String {
        if testsUniquelyFailed.count > 0 {
            return "Failed"
        } else {
            return "Passed"
        }
    }
    
    func htmlTextColor() -> String {
        if testsUniquelyFailed.count > 0 {
            return "color-error"
        } else {
            return "color-text"
        }
    }
}
