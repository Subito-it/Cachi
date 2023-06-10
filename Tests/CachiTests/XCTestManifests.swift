import XCTest

#if !canImport(ObjectiveC)
    public func allTests() -> [XCTestCaseEntry] {
        [
            testCase(CachiBrowserTests.allTests),
        ]
    }
#endif
