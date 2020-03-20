//
//  ApplicationModel.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//
import Foundation
import Dispatch
import Logging

import HealthEnclaveCommon

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.ApplicationModel")

class ApplicationModel {
    typealias CreateHotspotCreatedCallback = (_ wifiConfiguration: String) -> Void
    typealias CreateHotspotConnectedCallback = () -> Void
    
    private let wifiHotspotController = WifiHotspotController()
    
    func createHotspot(
        created: @escaping CreateHotspotCreatedCallback,
        connected: @escaping CreateHotspotConnectedCallback
    ) {
        logger.info("Creating Hotspot...")
        wifiHotspotController.create { ssid, password, ipAddress in
            let wifiConfiguration = WifiConfiguration(ssid: ssid, password: password, ipAddress: ipAddress)
            
            logger.info("WifiHotspot created:\n\(wifiConfiguration)")
            
            created(String(data: try! JSONEncoder().encode(wifiConfiguration), encoding: .utf8)!)
        }
    }
    
    func shutdownHotspot() {
        logger.info("Shutting down WifiHotspot..")
        wifiHotspotController.shutdown()
        logger.info("WifiHotspot shut down!")
    }
}
