import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(WifiConfigurationTests.allTests),
        testCase(CryptographicPrimitivesTests.allTests),
    ]
}
#endif
