//
//  WifiHotspotControllerMac.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 17.03.20.
//
#if os(macOS)
import Foundation
import Dispatch
import CoreWLAN
import SystemConfiguration
import Logging

import HealthEnclaveCommon

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.WifiHotspotControllerMac")

private typealias CreateContext = (ssid: String, password: String, created: CreateHotspotCallback)

private let contextKey = DispatchSpecificKey<CreateContext>()

private func ipNotificationCallback(store: SCDynamicStore, keys: CFArray, _: UnsafeMutableRawPointer?) {
    let context = DispatchQueue.getSpecific(key: contextKey)!
    let propertyList = SCDynamicStoreCopyValue(store, (keys as! [CFString])[0]);
    let ipAdresses = propertyList?["Addresses"] as? [String];
    
    if let ipAddress = ipAdresses?[0] {
        logger.debug("New IP address obtained: \(ipAddress)")
        context.created(context.ssid, context.password, ipAddress)
        SCDynamicStoreSetDispatchQueue(store, nil)
    }
}

private func randomPassword() -> String {
    return String(bytes: CryptographicPrimitives.randomBytes(length: 13), encoding: .ascii)!
}

class WifiHotspotController: WifiHotspotControllerProtocol {
    
    init() {
        wifiInterface = CWWiFiClient.shared().interface()!
    }
    
    private let wifiInterface: CWInterface
    
    func create(created: @escaping CreateHotspotCallback)  {
        logger.debug("Creating Hotspot with SSID \"\(ssid)\"...")
        
        let password = randomPassword()
        logger.debug("Created random WEP password: \(password)")
        
        let queue = DispatchQueue(label: "de.lschmierer.HealthEnclaveTerminal.WifiHotspotController", target: DispatchQueue.main)
        queue.setSpecific(key: contextKey, value: CreateContext(ssid: ssid, password: password, created: created))
        
        try! self.wifiInterface.startIBSSMode(withSSID: ssid.data(using: .utf8) ?? Data(),
                                              security: CWIBSSModeSecurity.WEP104,
                                              channel: 11,
                                              password: password)
        
        logger.debug("Hotspot started")
        logger.debug("Waiting for new IP address...")
        
        let store = SCDynamicStoreCreate(nil,
                                         "Health Enclave Terminal" as CFString,
                                         ipNotificationCallback,
                                         nil)!
        
        SCDynamicStoreSetNotificationKeys(store,
                                          ["State:/Network/Interface/\(self.wifiInterface.interfaceName!)/IPv4",
                                            "State:/Network/Interface/\(self.wifiInterface.interfaceName!)/IPv6"] as CFArray,
                                          nil)
        
        SCDynamicStoreSetDispatchQueue(store, queue)
    }
    
    func shutdown() {
        wifiInterface.disassociate()
    }
}
#endif
