//
//  ApplicationModel.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//
import Foundation
import Logging
import NIOSSL

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

import HealthEnclaveCommon

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.ApplicationModel")

enum ApplicationError: Error {
    case invalidCertificate(String)
    case invalidPrivateKey(String)
    case invalidNetwork(String)
    case invalidHotspot(Error)
    case notConnected
    case invalidSharedKey
    case missingSharedKey
    case noDocumentPermission
}

class ApplicationModel {
    private let _setupCompletedSubject = PassthroughSubject<Result<String, ApplicationError>, Never>()
    var setupCompletedSubject: AnyPublisher<Result<String, ApplicationError>, Never> {
        get { return _setupCompletedSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher() }
    }
    
    private let _deviceConnectedSubject = PassthroughSubject<Void, Never>()
    var deviceConnectedSubject: AnyPublisher<Void, Never> {
        get { return _deviceConnectedSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher() }
    }
    
    private let _sharedKeySetSubject = PassthroughSubject<DocumentsModel, Never>()
    var sharedKeySetSubject: AnyPublisher<DocumentsModel, Never> {
        get { return _sharedKeySetSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher() }
    }
    
    private var documentsModel: DocumentsModel?
    private var server: HealthEnclaveServer?
    private var serverDeviceConnectedSubscription: Cancellable?
    private var serverDeviceConnectionLostSubscription: Cancellable?
    
    func setupServer() {
        let port =  UserDefaults.standard.integer(forKey: "port")
        let pemCert = UserDefaults.standard.string(forKey: "cert")!
        guard let certificateChain = try? NIOSSLCertificate.fromPEMFile(pemCert),
            let derCert = try? certificateChain.first?.toDERBytes() else {
                _setupCompletedSubject.send(.failure(ApplicationError.invalidCertificate(pemCert)))
                return
        }
        
        let pemKey = UserDefaults.standard.string(forKey: "key")!
        guard let privateKey = try? NIOSSLPrivateKey(file: pemKey, format: .pem)
            else {
                _setupCompletedSubject
                    .send(.failure(ApplicationError.invalidPrivateKey(pemKey)))
                return
        }
        
        let interface = UserDefaults.standard.string(forKey: "interface")!
        guard let ipAddress = getIPAddress(ofInterface: interface) else { _setupCompletedSubject.send(.failure(ApplicationError.invalidNetwork("can not get ip address of interface \(interface)")))
            return
        }
        let ssid = UserDefaults.standard.string(forKey: "ssid")!
        let password = UserDefaults.standard.string(forKey: "password")!
        
        let wifiConfiguration = HealthEnclave_WifiConfiguration.with {
            $0.ssid = ssid
            $0.password = password
            $0.ipAddress = ipAddress
            $0.port = Int32(port)
            $0.derCert = Data(derCert)
        }
        
        logger.info("External Wifi Configuration:\n\(wifiConfiguration)")
        
        createServer(wifiConfiguration: wifiConfiguration,
                     certificateChain: certificateChain,
                     privateKey: privateKey)
        
        _setupCompletedSubject.send(.success(try! wifiConfiguration.jsonString()))
    }
    
    private func createServer(wifiConfiguration: HealthEnclave_WifiConfiguration,
                              certificateChain: [NIOSSLCertificate],
                              privateKey: NIOSSLPrivateKey) {
        server = HealthEnclaveServer(ipAddress: wifiConfiguration.ipAddress,
                                     port: Int(wifiConfiguration.port),
                                     certificateChain: certificateChain,
                                     privateKey: privateKey)
        serverDeviceConnectedSubscription = server?.deviceConnectedSubject
            .receive(on: DispatchQueue.global())
            .sink { [weak self] in
                guard let self = self else { return }
                self.documentsModel = DocumentsModel(documentStore: try! DocumentStore(for: self.server!.connectedDevice!),
                                                      server: self.server!)
                self._deviceConnectedSubject.send()
        }
        serverDeviceConnectionLostSubscription = server?.deviceConnectionLostSubject
            .receive(on: DispatchQueue.global())
            .sink() { [weak self] in
                logger.info("Destroying server...")
                self?.destroyServer()
                logger.info("Restarting server...")
                self?.setupServer()
        }
    }
    
    private func destroyServer() {
        server?.close()
        serverDeviceConnectedSubscription?.cancel()
        serverDeviceConnectionLostSubscription?.cancel()
    }
    
    func setSharedKey(data sharedKey: Data) throws {
        guard let documentsModel = documentsModel else {
            throw ApplicationError.notConnected
        }
        do {
            documentsModel.setSharedKey(try TerminalCryptography.SharedKey(data: sharedKey))
            _sharedKeySetSubject.send(documentsModel)
        } catch {
            throw ApplicationError.invalidSharedKey
        }
    }
}
