//
//  ApplicationModel.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//
import Foundation
import Dispatch
import Logging
import NIOSSL

import HealthEnclaveCommon

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.ApplicationModel")

enum ApplicationError: Error {
    case invalidCertificate
    case invalidNetwork(String)
}

class ApplicationModel {
    typealias ServerSetupCallback = (_ wifiConfiguration: Data) -> Void
    typealias DeviceConnectedCallback = () -> Void
    
    
    init() throws {
        #if os(Linux)
        wifiHotspotController = WifiHotspotControllerLinux()
        #else
        wifiHotspotController = nil
        #endif
    }
    
    private let wifiHotspotController: WifiHotspotControllerProtocol?
    private var server: HealthEnclaveServer?
    
    func setupServer(
        afterSetup setupCallback: @escaping ServerSetupCallback,
        onDeviceConnected deviceConnectedCallback: @escaping DeviceConnectedCallback
    ) throws {
        let port =  UserDefaults.standard.integer(forKey: "port")
        guard
            let pemCert = UserDefaults.standard.string(forKey: "cert"),
            let certificateChain = try? NIOSSLCertificate.fromPEMFile(pemCert),
            let leafCert = certificateChain.first,
            let derCert = try? leafCert.toDERBytes(),
            
            let pemKey = UserDefaults.standard.string(forKey: "key"),
            let privateKey = try? NIOSSLPrivateKey(file: pemKey, format: .pem)
            else {
                throw ApplicationError.invalidCertificate
        }
        
        let derCertBase64 = Data(derCert).base64EncodedString()
        
        if let wifiHotspotController = self.wifiHotspotController, UserDefaults.standard.bool(forKey: "hotspot") {
            logger.info("Creating Hotspot...")
            try wifiHotspotController.create { ssid, password, ipAddress, isWEP in
                let wifiConfiguration = WifiConfiguration(ssid: ssid, password: password, ipAddress: ipAddress, port: port, derCertBase64: derCertBase64)
                
                logger.info("WifiHotspot created:\n\(wifiConfiguration)")
                
                self.server = HealthEnclaveServer(ipAddress: ipAddress, port: port, certificateChain: certificateChain, privateKey: privateKey)
                
                setupCallback(try! JSONEncoder().encode(wifiConfiguration))
            }
        } else {
            let wifiInterface = UserDefaults.standard.string(forKey: "wifiInterface")!
            guard let ipAddress = getIPAddress(ofInterface: wifiInterface) else {
                throw ApplicationError.invalidNetwork("can not get ip address of interface \(wifiInterface)")
            }
            let ssid = UserDefaults.standard.string(forKey: "ssid")!
            let password = UserDefaults.standard.string(forKey: "password")!
            
            let wifiConfiguration = WifiConfiguration(ssid: ssid, password: password, ipAddress: ipAddress, port: port, derCertBase64: derCertBase64)
            
            server = HealthEnclaveServer(ipAddress: ipAddress, port: port, certificateChain: certificateChain, privateKey: privateKey)
            
            logger.info("External Wifi Configuration:\n\(wifiConfiguration)")
            
            setupCallback(try! JSONEncoder().encode(wifiConfiguration))
        }
    }
}
