//
//  NetworkUtils.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 02.04.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//

import SystemConfiguration.CaptiveNetwork

func getWifiSsid() -> String? {
    let interfaces = CNCopySupportedInterfaces() as! [CFString]
    
    for interface in interfaces {
        if let interfaceInfo = CNCopyCurrentNetworkInfo(interface) as Dictionary? {
            return interfaceInfo[kCNNetworkInfoKeySSID] as? String
        }
    }
    
    return nil
}
