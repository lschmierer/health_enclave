//
//  WifiHotspotController.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 05.03.20.
//

import Foundation

let defaultHotspotSSID = "Health Enclave Terminal"

enum HotsporError: Error {
    case invalidSSID
}

typealias CreateHotspotCallback = (_ ssid: String, _ password: String, _ ipAddress: String, _ isWEP: Bool) -> Void

protocol WifiHotspotControllerProtocol {
    func create(created: @escaping CreateHotspotCallback) throws
    
    func shutdown()
}
