import XCTest
@testable import HealthEnclaveCommon

final class WifiConfigurationTests: XCTestCase {
    func testInit() {
        let wifiConfiguration = WifiConfiguration(ssid: "ssid", password: "password", ipAddress: "ipAddress")
        
        XCTAssertEqual(wifiConfiguration.ssid, "ssid")
        XCTAssertEqual(wifiConfiguration.password, "password")
        XCTAssertEqual(wifiConfiguration.ipAddress, "ipAddress")
    }
    
    func testCodable() {
        let wifiConfiguration = WifiConfiguration(ssid: "ssid", password: "password", ipAddress: "ipAddredd")
        let json = "{\"password\":\"password\",\"ipAddress\":\"ipAddredd\",\"ssid\":\"ssid\"}".data(using: .utf8)!
        
        XCTAssertEqual(try! JSONEncoder().encode(wifiConfiguration), json)
        XCTAssertEqual(try! JSONDecoder().decode(WifiConfiguration.self, from: json), wifiConfiguration)
    }

    static var allTests = [
        ("testInit", testInit),
        ("testCodable", testCodable),
    ]
}
