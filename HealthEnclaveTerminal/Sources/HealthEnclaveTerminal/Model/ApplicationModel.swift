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
    case invalidCertificate(String)
    case invalidPrivateKey(String)
    case invalidNetwork(String)
}

class ApplicationModel {
    typealias SetupCompleteCallback = (_ wifiConfiguration: String) -> Void
    typealias DeviceConnectedCallback = () -> Void
    typealias SharedKeySetCallback = () -> Void
    
    init() throws {
        #if os(Linux)
        wifiHotspotController = WifiHotspotControllerLinux()
        #else
        wifiHotspotController = nil
        #endif
    }
    
    private var sharedKeySetCallback: SharedKeySetCallback?
    
    private let wifiHotspotController: WifiHotspotControllerProtocol?
    private var server: HealthEnclaveServer?
    
    func setupServer(
        onSetupComplete setupCompleteCallback: @escaping SetupCompleteCallback,
        onDeviceConnected deviceConnectedCallback: @escaping DeviceConnectedCallback,
        onSharedKeySet sharedKeySetCallback: @escaping SharedKeySetCallback
    ) throws {
        self.sharedKeySetCallback = sharedKeySetCallback
        
        let port =  UserDefaults.standard.integer(forKey: "port")
        let pemCert = UserDefaults.standard.string(forKey: "cert")!
        guard let certificateChain = try? NIOSSLCertificate.fromPEMFile(pemCert),
            let derCert = try? certificateChain.first?.toDERBytes() else {
                throw ApplicationError.invalidCertificate(pemCert)
        }
        
        let pemKey = UserDefaults.standard.string(forKey: "key")!
        guard let privateKey = try? NIOSSLPrivateKey(file: pemKey, format: .pem)
            else {
                throw ApplicationError.invalidPrivateKey(pemKey)
        }
        
        if let wifiHotspotController = self.wifiHotspotController, UserDefaults.standard.bool(forKey: "hotspot") {
            logger.info("Creating Hotspot...")
            try wifiHotspotController.create { ssid, password, ipAddress, isWEP in
                let wifiConfiguration = HealthEnclave_WifiConfiguration.with {
                    $0.ssid = ssid
                    $0.password = password
                    $0.ipAddress = ipAddress
                    $0.port = Int32(port)
                    $0.derCert = Data(derCert)
                }
                
                logger.info("WifiHotspot created:\n\(wifiConfiguration)")
                
                self.server = HealthEnclaveServer(ipAddress: ipAddress, port: port, certificateChain: certificateChain, privateKey: privateKey, onDeviceConnected: deviceConnectedCallback)
                
                setupCompleteCallback(try! wifiConfiguration.jsonString())
            }
        } else {
            let interface = UserDefaults.standard.string(forKey: "interface")!
            guard let ipAddress = getIPAddress(ofInterface: interface) else {
                throw ApplicationError.invalidNetwork("can not get ip address of interface \(interface)")
            }
            let ssid = UserDefaults.standard.string(forKey: "ssid")!
            let password = UserDefaults.standard.string(forKey: "password")!
            
            let wifiConfiguration = HealthEnclave_WifiConfiguration.with {
                $0.ssid = ssid
                $0.password = password
                $0.ipAddress = ipAddress
                $0.port = Int32(port)
                $0.derCert = Data(derCert)
            }
            
            server = HealthEnclaveServer(ipAddress: ipAddress, port: port, certificateChain: certificateChain, privateKey: privateKey, onDeviceConnected: deviceConnectedCallback)
            
            logger.info("External Wifi Configuration:\n\(wifiConfiguration)")
            
            setupCompleteCallback(try! wifiConfiguration.jsonString())
        }
    }
    
    func setSharedKey(data sharedKey: Data) {
        debugPrint(sharedKey)
        sharedKeySetCallback?()
    }
}
