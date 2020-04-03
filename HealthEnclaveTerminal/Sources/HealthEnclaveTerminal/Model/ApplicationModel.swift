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
    typealias ServerSetupCallback = (_ wifiConfiguration: String) -> Void
    typealias DeviceConnectedCallback = () -> Void
    
    
    init() throws {
        #if os(Linux)
        wifiHotspotController = WifiHotspotControllerLinux()
        #else
        wifiHotspotController = nil
        #endif
    }
    
    private let wifiHotspotController: WifiHotspotControllerProtocol?
    
    func setupServer(
        afterSetup setupCallback: @escaping ServerSetupCallback,
        onDeviceConnected deviceConnectedCallback: @escaping DeviceConnectedCallback
    ) throws {
        if let wifiHotspotController = self.wifiHotspotController, UserDefaults.standard.bool(forKey: "hotspot") {
            logger.info("Creating Hotspot...")
            try wifiHotspotController.create { ssid, password, ipAddress, isWEP in
                let wifiConfiguration = WifiConfiguration(ssid: ssid, password: password, ipAddress: ipAddress)
                
                logger.info("WifiHotspot created:\n\(wifiConfiguration)")
                
                self.setupSocket(onDeviceConnected: deviceConnectedCallback)
                
                setupCallback(String(data: try! JSONEncoder().encode(wifiConfiguration), encoding: .utf8)!)
            }
        } else {
            let wifiInterface = UserDefaults.standard.string(forKey: "wifiInterface")!
            guard let ipAdress = getIPAddress(ofInterface: wifiInterface) else {
                throw ApplicationError.invalidNetwork("can not get ip address of interface \(wifiInterface)")
            }
            let ssid = UserDefaults.standard.string(forKey: "ssid")!
            let password = UserDefaults.standard.string(forKey: "password")!
            
            let wifiConfiguration = WifiConfiguration(ssid: ssid, password: password, ipAddress: ipAdress)
            setupSocket(onDeviceConnected: deviceConnectedCallback)
            
            logger.info("External Wifi Configuration:\n\(wifiConfiguration)")
            
            setupCallback(String(data: try! JSONEncoder().encode(wifiConfiguration), encoding: .utf8)!)
        }
    }
    
    private func setupSocket(onDeviceConnected deviceConnectedCallback: @escaping DeviceConnectedCallback) {
        // setup socket
        // wait for connection to socket
        
    }
    
    func shutdownServer() {
        if let wifiHotspotController = self.wifiHotspotController, UserDefaults.standard.bool(forKey: "hotspot") {
            logger.info("Shutting down WifiHotspot..")
            wifiHotspotController.shutdown()
            logger.info("WifiHotspot shut down!")
        }
    }
}
