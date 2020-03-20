import XCTest

import HealthEnclaveCommonTests

var tests = [XCTestCaseEntry]()
tests += WifiConfigurationTests.allTests()
tests += CryptographicPrimitivesTests.allTests()
XCTMain(tests)
