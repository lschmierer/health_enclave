import XCTest
@testable import HealthEnclaveCommon

final class CryptographicPrimitivesTests: XCTestCase {
    func testRandomBytes() {
        XCTAssertEqual(CryptographicPrimitives.randomBytes(length: 7).count, 7)
        XCTAssertNotEqual(CryptographicPrimitives.randomBytes(length: 7), CryptographicPrimitives.randomBytes(length: 7))
    }

    static var allTests = [
        ("testRandomBytes", testRandomBytes),
    ]
}
