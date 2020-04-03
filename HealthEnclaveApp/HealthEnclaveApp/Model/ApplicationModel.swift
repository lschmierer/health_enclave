//
//  ApplicationModel.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 20.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import os
import NetworkExtension

import HealthEnclaveCommon

enum ApplicationError: Error {
    case wifiInvalidConfiguration
    case wifi(Error?)
}

extension ApplicationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .wifiInvalidConfiguration:
            return "Invalid Wifi Configuration"
        case .wifi(let error):
            if let errorDescription = error?.localizedDescription {
                return errorDescription.prefix(1).capitalized + errorDescription.dropFirst()
            }
        }
        return "Unknown Error"
    }
}

class ApplicationModel: ObservableObject {
    typealias ConnectedCallback = (_ result: Result<Void, ApplicationError>) -> Void
    
    @Published public internal(set) var isConnecting = false
    @Published public internal(set) var isConnected = false
    
    func connect(to jsonWifiConfiguration: String, onConnect connectedCallback: @escaping ConnectedCallback) {
        isConnecting = true
        guard let wifiConfiguration = try? JSONDecoder().decode(WifiConfiguration.self, from: jsonWifiConfiguration.data(using: .utf8)!) else {
            os_log(.info, "Invalid WifiConfiguration: %@", jsonWifiConfiguration)
            connectedCallback(.failure(.wifiInvalidConfiguration))
            self.isConnecting = false
            self.isConnected = false
            return
        }
        
        os_log(.info, "Connecting to Wifi: %@", String(reflecting: wifiConfiguration))
        let hotspotConfiguration =  NEHotspotConfiguration(ssid: wifiConfiguration.ssid, passphrase: wifiConfiguration.password, isWEP: false)
        hotspotConfiguration.joinOnce = false
        
        NEHotspotConfigurationManager.shared.apply(hotspotConfiguration) { rawError in
            var nsError = rawError as NSError?
            
            // Throw away non-error errors
            if let error = nsError, error.domain == NEHotspotConfigurationErrorDomain {
                if(error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue) {
                    os_log(.info, "Wifi already connected");
                    nsError = nil
                }
            }
            
            if let error = nsError  {
                os_log(.error, "Error applying Hotspot Configuration: %@", error.debugDescription)
                connectedCallback(Result.failure(.wifi(error)))
                self.isConnected = false
                self.isConnecting = false
            } else {
                os_log(.info, "Hotspot Configuration added")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if let ssid = getWifiSsid(), ssid == wifiConfiguration.ssid {
                        os_log(.info, "Wifi connected");
                        connectedCallback(Result.success(()))
                        self.isConnected = true
                    } else {
                        os_log(.error, "Connected to wrong SSID")
                        connectedCallback(Result.failure(.wifi(nil)))
                        self.isConnected = false
                    }
                    self.isConnecting = false
                }
            }
        }
    }
    
    func diconnect() {
        if(isConnected) {
            isConnected = false
            os_log(.info, "Disconnected");
        }
    }
}
