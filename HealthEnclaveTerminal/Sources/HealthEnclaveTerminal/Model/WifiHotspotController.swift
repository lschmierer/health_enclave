//
//  WifiHotspotController.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 05.03.20.
//

let ssid = "Health Enclave Terminal"
typealias CreateHotspotCallback = (_ ssid: String, _ password: String, _ ipAddress: String) -> Void

protocol WifiHotspotControllerProtocol {
    func create(created: @escaping CreateHotspotCallback)
    
    func shutdown()
}
