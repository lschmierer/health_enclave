//
//  ApplicationModel.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 20.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//

import NetworkExtension
import SystemConfiguration.CaptiveNetwork

import HealthEnclaveCommon

private func getWifiSsid() -> String? {
    var ssid: String?
    if let interfaces = CNCopySupportedInterfaces() as NSArray? {
        for interface in interfaces {
            if let interfaceInfo = CNCopyCurrentNetworkInfo(interface as! CFString) as NSDictionary? {
                ssid = interfaceInfo[kCNNetworkInfoKeySSID as String] as? String
                break
            }
        }
    }
    return ssid
}

class ApplicationModel {
    private var wifiConfiguration: WifiConfiguration?
    
    var isConnected: Bool {
        get {
            return wifiConfiguration != nil ? getWifiSsid() == wifiConfiguration?.ssid : false
        }
    }
    
    func connect(to jsonWifiConfiguration: String) {
        wifiConfiguration = try! JSONDecoder().decode(WifiConfiguration.self,
                                                          from: jsonWifiConfiguration.data(using: .utf8)!)
        
        
        
        NEHotspotConfigurationManager.shared.getConfiguredSSIDs { (wifiList) in
            wifiList.forEach { NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: $0) }
            // ... from here you can use your usual approach to autoconnect to your network
        }
        
        var hotspotConfiguration =  NEHotspotConfiguration(ssid: wifiConfiguration!.ssid, passphrase: wifiConfiguration!.password, isWEP: true)
        hotspotConfiguration.joinOnce = false
        
        NEHotspotConfigurationManager.shared.apply(hotspotConfiguration) { error in
            if let error = error {
                debugPrint(error)
                debugPrint("error \(error.localizedDescription)")
            } else {
                debugPrint("no error")
            }
        }
    }
}
