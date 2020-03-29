//
//  WifiConfiguration.swift
//  
//
//  Created by Lukas Schmierer on 05.03.20.
//

public struct WifiConfiguration: Codable, Equatable {
    public init(ssid: String, password: String, ipAddress: String, isWEP: Bool) {
        self.ssid = ssid
        self.password = password
        self.ipAddress = ipAddress
        self.isWEP = isWEP
    }
    
    public let ssid: String
    public let password: String
    public let ipAddress: String
    public let isWEP: Bool
}
