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

enum ApplicationError: Error {
    case invalidNetwork(String)
}

class ApplicationModel {
    typealias ServerCreatedCallback = (_ wifiConfiguration: String) -> Void
    typealias DeviceConnectedCallback = () -> Void
    
    
    init() throws {
        wifiHotspotController = WifiHotspotController()
    }
    
    private let wifiHotspotController: WifiHotspotControllerProtocol
    
    func setupServer(
        created: @escaping ServerCreatedCallback,
        connected: @escaping DeviceConnectedCallback
    ) throws {
        if (UserDefaults.standard.bool(forKey: "hotspot")) {
            logger.info("Creating Hotspot...")
            try wifiHotspotController.create { ssid, password, ipAddress, isWEP in
                let wifiConfiguration = WifiConfiguration(ssid: ssid, password: password, ipAddress: ipAddress, isWEP: isWEP)
                
                logger.info("WifiHotspot created:\n\(wifiConfiguration)")
                
                created(String(data: try! JSONEncoder().encode(wifiConfiguration), encoding: .utf8)!)
            }
        } else {
            let wifiInterface = UserDefaults.standard.string(forKey: "wifiInterface")!
            guard let ipAdress = getIPAddress(ofInterface: wifiInterface) else {
                throw ApplicationError.invalidNetwork("can not get ip address of interface \(wifiInterface)")
            }
            let ssid = UserDefaults.standard.string(forKey: "ssid")!
            let password = UserDefaults.standard.string(forKey: "password")!
            let isWEP = UserDefaults.standard.bool(forKey: "isWEP")
            
            let wifiConfiguration = WifiConfiguration(ssid: ssid, password: password, ipAddress: ipAdress, isWEP: isWEP)
            
            logger.info("External Wifi Configuration:\n\(wifiConfiguration)")
            
            created(String(data: try! JSONEncoder().encode(wifiConfiguration), encoding: .utf8)!)
        }
    }
    
    func shutdownServer() {
        if(UserDefaults.standard.bool(forKey: "hotspot")) {
            logger.info("Shutting down WifiHotspot..")
            wifiHotspotController.shutdown()
            logger.info("WifiHotspot shut down!")
        }
    }
}
