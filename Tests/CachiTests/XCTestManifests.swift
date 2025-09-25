import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    [
        testCase(CachiBrowserTests.allTests),
        testCase(AttachmentViewerConfigurationTests.allTests)
    ]
}
#endif
