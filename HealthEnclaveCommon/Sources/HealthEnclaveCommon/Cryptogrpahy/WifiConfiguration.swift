//
//  WifiConfiguration.swift
//  
//
//  Created by Lukas Schmierer on 05.03.20.
//

public struct WifiConfiguration: Codable, Equatable {
    public init(ssid: String, password: String, ipAddress: String, port: Int, derCertBase64: String) {
        self.ssid = ssid
        self.password = password
        self.ipAddress = ipAddress
        self.port = port
        self.derCertBase64 = derCertBase64
    }
    
    public let ssid: String
    public let password: String
    public let ipAddress: String
    public let port: Int
    public let derCertBase64: String
}
