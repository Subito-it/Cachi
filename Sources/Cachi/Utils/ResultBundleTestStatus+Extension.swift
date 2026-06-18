extension ResultBundle {
    func htmlTitle() -> String {
        if let branchName = userInfo?.branchName, let commitHash = userInfo?.commitHash {
            "\(branchName) - \(commitHash)"
        } else {
            identifier
        }
    }

    func htmlSubtitle() -> String {
        userInfo?.commitMessage ?? ""
    }
}

extension ResultBundle {
    func htmlStatusImageUrl(for test: ResultBundle.Test) -> String {
        if test.status == .success {
            return ImageRoute.passedTestImageUrl()
        }

        if testsUniquelyFailed.contains(where: { $0.matches(test) }) || test.groupName == "System Failures" {
            return ImageRoute.failedTestImageUrl()
        } else {
            return ImageRoute.retriedTestImageUrl()
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
            return ImageRoute.failedTestImageUrl()
        } else {
            return ImageRoute.passedTestImageUrl()
        }
    }

    func htmlStatusTitle() -> String {
        if testsUniquelyFailed.count > 0 {
            "Failed"
        } else {
            "Passed"
        }
    }

    func htmlTextColor() -> String {
        if testsUniquelyFailed.count > 0 {
            "color-error"
        } else {
            "color-text"
        }
    }
}

// Same presentation logic as the `ResultBundle` helpers above, driven by the precomputed rollup
// columns so the results-list view needs no test rows. Kept in sync with the bundle versions.
extension ResultStore.ResultSummary {
    var htmlTitle: String {
        if let branchName, let commitHash {
            "\(branchName) - \(commitHash)"
        } else {
            identifier
        }
    }

    var htmlSubtitle: String {
        commitMessage ?? ""
    }

    func htmlStatusImageUrl(includeSystemFailures: Bool) -> String {
        var failedTestCount = uniquelyFailedCount
        if includeSystemFailures {
            failedTestCount += failedBySystemCount
        }
        return failedTestCount > 0 ? ImageRoute.failedTestImageUrl() : ImageRoute.passedTestImageUrl()
    }

    var htmlStatusTitle: String {
        uniquelyFailedCount > 0 ? "Failed" : "Passed"
    }

    var htmlTextColor: String {
        uniquelyFailedCount > 0 ? "color-error" : "color-text"
    }
}
