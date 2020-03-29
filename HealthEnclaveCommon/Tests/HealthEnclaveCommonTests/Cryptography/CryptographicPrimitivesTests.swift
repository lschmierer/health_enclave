import XCTest
@testable import HealthEnclaveCommon

final class CryptographicPrimitivesTests: XCTestCase {
    func testRandomBytes() {
        XCTAssertEqual(CryptographicPrimitives.randomBytes(count: 7).count, 7)
        XCTAssertNotEqual(CryptographicPrimitives.randomBytes(count: 7), CryptographicPrimitives.randomBytes(count: 7))
    }

    static var allTests = [
        ("testRandomBytes", testRandomBytes),
    ]
}
