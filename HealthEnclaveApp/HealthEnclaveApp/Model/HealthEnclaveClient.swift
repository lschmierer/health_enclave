//
//  HealthEnclaveClient.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 04.04.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import os
import Foundation
import Combine
import SwiftProtobuf
import GRPC
import NIO
import NIOSSL

import HealthEnclaveCommon

private let keepAliveInterval: TimeAmount = .seconds(1)

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

class HealthEnclaveClient {
    private let group: EventLoopGroup
    private var client: HealthEnclave_HealthEnclaveClient
    
    private var keepAliveCall: BidirectionalStreamingCall<SwiftProtobuf.Google_Protobuf_Empty, SwiftProtobuf.Google_Protobuf_Empty>?
    private var keepAliveTask: RepeatedTask?
    
    private let _missingDocumentsForDeviceSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never>()
    var missingDocumentsForDeviceSubject: AnyPublisher<HealthEnclave_DocumentIdentifier, Never> {
        get { return _missingDocumentsForDeviceSubject.eraseToAnyPublisher() }
    }
    
    private let _missingDocumentsForTerminalSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never>()
    var missingDocumentsForTerminalSubject: AnyPublisher<HealthEnclave_DocumentIdentifier, Never> {
        get { return _missingDocumentsForTerminalSubject.eraseToAnyPublisher() }
    }
    
    private let _missingEncryptedDocumentKeyForTerminalSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never>()
    var missingEncryptedDocumentKeyForTerminalSubject: AnyPublisher<HealthEnclave_DocumentIdentifier, Never> {
        get { return _missingEncryptedDocumentKeyForTerminalSubject.eraseToAnyPublisher() }
    }
    
    private let _missingTwofoldEncryptedDocumentKeyForTerminalSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never>()
    var missingTwofoldEncryptedDocumentKeyForTerminalSubject: AnyPublisher<HealthEnclave_DocumentIdentifier, Never> {
        get { return _missingTwofoldEncryptedDocumentKeyForTerminalSubject.eraseToAnyPublisher() }
    }
    
    class func create(ipAddress: String,
                      port: Int,
                      certificate: NIOSSLCertificate,
                      deviceIdentifier: DeviceCryptography.DeviceIdentifier,
                      advertisedDocumentsMetadata: [HealthEnclave_DocumentMetadata]) -> AnyPublisher<HealthEnclaveClient, ApplicationError> {
        let client = HealthEnclaveClient(ipAddress: ipAddress, port: port, certificate: certificate, deviceIdentifier: deviceIdentifier)
        return client.establishConnection(advertisedDocumentsMetadata)
            .map { client }
            .eraseToAnyPublisher()
    }
    
    private init(ipAddress: String,
                 port: Int,
                 certificate: NIOSSLCertificate,
                 deviceIdentifier: DeviceCryptography.DeviceIdentifier) {
        group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
        
        let configuration = ClientConnection.Configuration(
            target: .hostAndPort(ipAddress, port),
            eventLoopGroup: group,
            tls: ClientConnection.Configuration.TLS(
                trustRoots: .certificates([certificate]),
                certificateVerification: .noHostnameVerification),
            // In this local setup, TLS conenction is expected to work on first try.
            connectionBackoff: nil
        )
        let channel = ClientConnection(configuration: configuration)
        
        let callOptions = CallOptions(customMetadata: [
            "deviceIdentifier": deviceIdentifier.hexEncodedString
        ])
        
        client = HealthEnclave_HealthEnclaveClient(channel: channel, defaultCallOptions: callOptions)
    }
    
    private func establishConnection(_ advertisedDocumentsMetadata: [HealthEnclave_DocumentMetadata]) -> AnyPublisher<Void, ApplicationError>  {
        let subject = PassthroughSubject<Void, ApplicationError>()
        var sentToSubject = false
        
        self.keepAliveCall = self.client.keepAlive { _ in
            if !sentToSubject {
                sentToSubject = true
                subject.send(Void())
            }
        }
        
        _ = self.keepAliveCall?.status.always { [weak subject] result in
            guard let subject = subject else { return }
            guard case let .success(status) = result, status.code == .ok else {
                switch result {
                case .success(let status):
                    let error = ApplicationError.connection(status.message)
                    subject.send(completion: .failure(error))
                case .failure(let error):
                    subject.send(completion: .failure(.connection(error)))
                }
                return
            }
        }
        
        self.keepAliveTask = self.group.next()
            .scheduleRepeatedTask(initialDelay: .seconds(0), delay: keepAliveInterval, { [weak self] task in
                if let keepAliveCall = self?.keepAliveCall {
                    os_log(.info, "Send KeepAlive")
                    _ = keepAliveCall.sendMessage(Google_Protobuf_Empty()).always({ result in
                        os_log(.info, "KeepAlive sent: %@", String(reflecting: result))
                    });
                } else {
                    task.cancel()
                }
        })
        
        let streamingCall = client.advertiseDocumentsToTerminal()
        _ = streamingCall.sendMessages(advertisedDocumentsMetadata)
        _ = streamingCall.sendEnd()
        
        _ = self.client.missingDocumentsForDevice(Google_Protobuf_Empty()) { [weak self] documentIdentifier in
            self?._missingDocumentsForDeviceSubject.send(documentIdentifier)
        }
        
        _ = self.client.missingDocumentsForTerminal(Google_Protobuf_Empty()) { [weak self] documentIdentifier in
            self?._missingDocumentsForTerminalSubject.send(documentIdentifier)
        }
        
        _ = self.client.missingEncryptedDocumentKeysForTerminal(Google_Protobuf_Empty()) { [weak self] documentIdentifier in
            self?._missingEncryptedDocumentKeyForTerminalSubject.send(documentIdentifier)
        }
        
        _ = self.client.missingTwofoldEncryptedDocumentKeysForTerminal(Google_Protobuf_Empty()) { [weak self] documentIdentifier in
            self?._missingTwofoldEncryptedDocumentKeyForTerminalSubject.send(documentIdentifier)
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    func transferDocumentsToDevice(with identifier: HealthEnclave_DocumentIdentifier) -> AnyPublisher<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Error> {
        let documentStreamSubject = PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Error>()
        
        var dataLength = 0
        _ = client.transferDocumentToDevice(identifier) { documentChunked in
            documentStreamSubject.send(documentChunked)
            if case let .chunk(chunk) = documentChunked.content {
                dataLength += chunk.count
            }
        }
        .status.map { status in
            if status == .ok {
                documentStreamSubject.send(completion: .finished)
            } else {
                documentStreamSubject.send(completion: .failure(status))
            }
        }
        return documentStreamSubject.eraseToAnyPublisher()
    }
    
    func transferEncryptedDocumentToTerminal(chunks: [HealthEnclave_TwofoldEncyptedDocumentChunked]) {
        let transferEncryptedDocumentToTerminalCall = client.transferDocumentToTerminal()
        
        var chunkIterator = chunks.makeIterator()
        self.group.next().scheduleRepeatedAsyncTask(initialDelay: .seconds(0), delay: .seconds(0)) { task in
            if let chunk = chunkIterator.next() {
                return transferEncryptedDocumentToTerminalCall.sendMessage(chunk)
            } else {
                task.cancel()
                return transferEncryptedDocumentToTerminalCall.sendEnd()
            }
        }
    }
    
    func transferEncryptedDocumentKeyToTerminal(_ encryptedKey: HealthEnclave_EncryptedDocumentKey,
                                                with identifier: HealthEnclave_DocumentIdentifier) {
        _ = client.transferEncryptedDocumentKeyToTerminal(HealthEnclave_EncryptedDocumentKeyWithId.with({
            $0.id = identifier
            $0.key = encryptedKey
        }))
    }
    
    func transferTwofoldEncryptedDocumentKeyToTerminal(_ twofoldEncryptedKey: HealthEnclave_TwofoldEncryptedDocumentKey,
                                                       with identifier: HealthEnclave_DocumentIdentifier) {
        _ = client.transferTwofoldEncryptedDocumentKeyToTerminal(HealthEnclave_TwofoldEncryptedDocumentKeyWithId.with({
            $0.id = identifier
            $0.key = twofoldEncryptedKey
        }))
    }
    
    func disconnect() {
        keepAliveTask?.cancel()
        try? keepAliveCall?.sendEnd().wait()
        try? client.channel.close().wait()
        try? group.syncShutdownGracefully()
    }
}
