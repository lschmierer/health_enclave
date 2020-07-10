//
//  ApplicationModel.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 20.03.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import os
import NetworkExtension
import Combine
import NIOSSL
import BIP39

import HealthEnclaveCommon

enum ApplicationError: Error {
    case wifiInvalidConfiguration
    case wifi(Error?)
    case connection(Error?)
    case unknown
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
            return "Wifi Error"
        case .connection(let error):
            if let errorDescription = error?.localizedDescription {
                return errorDescription.prefix(1).capitalized + errorDescription.dropFirst()
            }
            return "Connection Error"
        case .unknown:
            return "Unknown"
        }
    }
}

class ApplicationModel: ObservableObject {
    @Published public internal(set) var deviceKey: DeviceCryptography.DeviceKey?
    @Published public internal(set) var mnemonicPhrase: [String]?
    @Published public internal(set) var isConnecting = false
    @Published public internal(set) var isConnected = false
    @Published public internal(set) var isTransfering = true
    
    private let deviceIdentifier: DeviceCryptography.DeviceIdentifier
    private var documentsModel: DocumentsModel?
    private var documentStore: DocumentStore?
    private var client: HealthEnclaveClient?
    
    init() {
        if let hexDeviceIdentifier = UserDefaults.standard.object(forKey: "deviceIdentifier") as? String {
            deviceIdentifier = DeviceCryptography.DeviceIdentifier(hexEncoded: hexDeviceIdentifier)!
        } else {
            deviceIdentifier = DeviceCryptography.DeviceIdentifier()
            UserDefaults.standard.set(deviceIdentifier.hexEncodedString, forKey: "deviceIdentifier")
        }
        if UserDefaults.standard.bool(forKey: "deviceKeySet") {
            deviceKey = KeyChain.load()
        }
    }
    
    func generateDeviceKey() {
        let mnemonic = Mnemonic()
        self.mnemonicPhrase = mnemonic.phrase
    }
    
    func setDeviceKey(from mnemonicPhrase: [String]) throws {
        let mnemonic = try Mnemonic(phrase: mnemonicPhrase)
        self.mnemonicPhrase = mnemonicPhrase
        deviceKey = try! DeviceCryptography.DeviceKey(data: Data(mnemonic.seed[..<32]))
        try! KeyChain.save(key: deviceKey!)
        UserDefaults.standard.set(true, forKey: "deviceKeySet")
    }
    
    
    func connect(to jsonWifiConfiguration: String) -> AnyPublisher<Void, ApplicationError> {
        self.isConnecting = true
        guard
            let wifiConfiguration = try? HealthEnclave_WifiConfiguration(jsonString: jsonWifiConfiguration),
            let certificate = try? NIOSSLCertificate(bytes: [UInt8](wifiConfiguration.derCert), format: .der)
        else {
            os_log(.info, "Invalid WifiConfiguration: %@", jsonWifiConfiguration)
            self.isConnecting = false
            self.isConnected = false
            return Fail(error: ApplicationError.wifiInvalidConfiguration)
                .eraseToAnyPublisher()
        }
        
        os_log(.info, "Connecting to Wifi: %@", String(reflecting: wifiConfiguration))
        return Self.connectWifi(ssid: wifiConfiguration.ssid, passphrase: wifiConfiguration.password)
            .flatMap { [weak self] () -> AnyPublisher<Void, ApplicationError> in
                guard let self = self else { return Fail(error: .unknown).eraseToAnyPublisher() }
                os_log(.info, "Creating client")
                return self.createClient(ipAddress: wifiConfiguration.ipAddress,
                                         port: Int(wifiConfiguration.port),
                                         certificate: certificate)
            }
            .receive(on: DispatchQueue.main)
            .map { [weak self] in
                self?.isConnected = true
                self?.isConnecting = false
            }
            .mapError { [weak self] error in
                self?.isConnected = false
                self?.isConnecting = false
                return error
            }
            .eraseToAnyPublisher()
    }
    
    private static func connectWifi(ssid: String, passphrase: String) -> Future<Void, ApplicationError> {
        return Future() { promise in
            let hotspotConfiguration =  NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
            hotspotConfiguration.joinOnce = true
            
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
                    os_log(.error, "Error applying Hotspot Configuration: %@", error.localizedDescription)
                    promise(.failure(.wifi(error)))
                } else {
                    os_log(.info, "Hotspot Configuration added")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if let connectedSsid = getWifiSsid(), connectedSsid == ssid {
                            os_log(.info, "Wifi connected");
                            promise(.success(()))
                        } else {
                            os_log(.error, "Connected to wrong SSID")
                            promise(.failure(.wifi(nil)))
                        }
                    }
                }
            }
        }
    }
    
    private func createClient(ipAddress: String,
                              port: Int,
                              certificate: NIOSSLCertificate) -> AnyPublisher<Void, ApplicationError> {
        documentStore = try! DocumentStore(for: self.deviceIdentifier)
        return HealthEnclaveClient.create(ipAddress: ipAddress,
                                          port: port,
                                          certificate: certificate,
                                          deviceIdentifier: self.deviceIdentifier)
            .map { [weak self] client in
                guard let self = self else { return }
                self.client = client
                self.documentsModel = DocumentsModel(deviceKey: self.deviceKey!,
                                                    documentStore: self.documentStore!,
                                                    client: client)
            }
            .eraseToAnyPublisher()
    }
    
    func disconnect() {
        if(isConnected) {
            client?.disconnect()
            isConnected = false
            os_log(.info, "Disconnected");
        }
    }
    
    deinit {
        disconnect()
    }
}
