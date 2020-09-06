//
//  NetworkUtils.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 29.03.20.
//

import Foundation
import NetUtils

// Return IP address of given interface.
func getIPAddress(ofInterface interfaceName: String) -> String? {
    for interface in Interface.allInterfaces() {
        if interface.family == .ipv4 && interface.name == interfaceName {
            return interface.address
        }
    }
    return nil
}
