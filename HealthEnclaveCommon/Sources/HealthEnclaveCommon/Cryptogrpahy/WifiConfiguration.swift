//
//  WifiConfiguration.swift
//  
//
//  Created by Lukas Schmierer on 05.03.20.
//

public struct WifiConfiguration: Codable, Equatable {
    public init(ssid: String, password: String, ipAddress: String) {
        self.ssid = ssid
        self.password = password
        self.ipAddress = ipAddress
    }
    
    public let ssid: String
    public let password: String
    public let ipAddress: String
}
