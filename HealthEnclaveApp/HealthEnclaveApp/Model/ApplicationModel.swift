//
//  ApplicationModel.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 20.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import os
import NetworkExtension

import NIOSSL

import HealthEnclaveCommon

enum ApplicationError: Error {
    case wifiInvalidConfiguration
    case wifi(Error?)
    case connection
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
        case .connection:
            return "Connection Error"
        }
        return "Unknown Error"
    }
}

class ApplicationModel: ObservableObject {
    typealias ConnectedCallback = (_ result: Result<Void, ApplicationError>) -> Void
    
    @Published public internal(set) var isConnecting = false
    @Published public internal(set) var isConnected = false
    public internal(set) var isTransfering = true
    
    private var client: HealthEnclaveClient?
    
    func connect(to jsonWifiConfiguration: String, onConnect connectedCallback: @escaping ConnectedCallback) {
        isConnecting = true
        guard
            let wifiConfiguration = try? JSONDecoder().decode(WifiConfiguration.self, from: jsonWifiConfiguration.data(using: .utf8)!),
            let derBytes = Data(base64Encoded: wifiConfiguration.derCertBase64),
            let certificate = try? NIOSSLCertificate(bytes: [UInt8](derBytes), format: .der)
            else {
                os_log(.info, "Invalid WifiConfiguration: %@", jsonWifiConfiguration)
                connectedCallback(.failure(.wifiInvalidConfiguration))
                self.isConnecting = false
                self.isConnected = false
                return
        }
        
        os_log(.info, "Connecting to Wifi: %@", String(reflecting: wifiConfiguration))
        connectWifi(ssid: wifiConfiguration.ssid, passphrase: wifiConfiguration.password) { result in
            if case .failure = result {
                self.isConnected = false
                self.isConnecting = false
                connectedCallback(result)
            } else {
                self.createClient(ipAddress: wifiConfiguration.ipAddress, port: wifiConfiguration.port, certificate: certificate) { result in
                    if case .failure = result {
                        self.isConnected = false
                        self.isConnecting = false
                        connectedCallback(result)
                    } else {
                        self.isConnected = true
                        self.isConnecting = false
                        connectedCallback(.success(()))
                    }
                }
            }
        }
    }
    
    private func connectWifi(ssid: String, passphrase: String, onConnect connectedCallback: @escaping ConnectedCallback) {
        let hotspotConfiguration =  NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
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
            } else {
                os_log(.info, "Hotspot Configuration added")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if let connectedSsid = getWifiSsid(), connectedSsid == ssid {
                        os_log(.info, "Wifi connected");
                        connectedCallback(.success(()))
                    } else {
                        os_log(.error, "Connected to wrong SSID")
                        connectedCallback(.failure(.wifi(nil)))
                    }
                }
            }
        }
    }
    
    private func createClient(ipAddress: String,
                              port: Int,
                              certificate: NIOSSLCertificate,
                              onConnect connectedCallback: @escaping ConnectedCallback) {
        client = HealthEnclaveClient(ipAddress: ipAddress, port: port, certificate: certificate) {error in
            os_log(.error, "GRPC connection error: %@", error.localizedDescription)
            self.disconnect()
        }
        
        let _ = client?.connect().always({ result in
            DispatchQueue.main.async {
                if case .failure = result {
                    connectedCallback(.failure(.connection))
                } else {
                    connectedCallback(.success(()))
                }
            }
        })
    }
    
    func disconnect() {
        if(isConnected) {
            client = nil
            isConnected = false
            os_log(.info, "Disconnected");
        }
    }
    
    deinit {
        disconnect()
    }
}