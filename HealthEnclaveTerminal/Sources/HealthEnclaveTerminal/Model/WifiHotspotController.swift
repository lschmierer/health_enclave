//
//  WifiHotspotController.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 05.03.20.
//

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

let defaultHotspotSSID = "Health Enclave Terminal"

enum HotsporError: Error {
    case invalidSSID
}

struct HotsporConfiguration {
    let ssid: String
    let password: String
    let ipAddress: String
    let isWEP: Bool
}

protocol WifiHotspotControllerProtocol {
    func create() -> Future<HotsporConfiguration, HotsporError>
}
