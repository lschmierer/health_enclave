import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(HealthEnclaveCommonTests.allTests),
    ]
}
#endif
