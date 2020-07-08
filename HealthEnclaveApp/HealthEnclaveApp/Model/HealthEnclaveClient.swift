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
    private let _documentReceivedSubject = PassthroughSubject<PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Error>, Never>()
    var documentReceivedSubject: AnyPublisher<PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Error>, Never> {
        get { return _documentReceivedSubject.eraseToAnyPublisher() }
    }
    
    private let group: EventLoopGroup
    private var client: HealthEnclave_HealthEnclaveClient
    private let deviceIdentifier: DeviceCryptography.DeviceIdentifier
    private var keepAliveCall: BidirectionalStreamingCall<SwiftProtobuf.Google_Protobuf_Empty, SwiftProtobuf.Google_Protobuf_Empty>?
    private var missingDocumentsCall: ServerStreamingCall<SwiftProtobuf.Google_Protobuf_Empty, HealthEnclaveCommon.HealthEnclave_DocumentIdentifier>?
    
    class func create(ipAddress: String,
                      port: Int,
                      certificate: NIOSSLCertificate,
                      deviceIdentifier: DeviceCryptography.DeviceIdentifier) -> AnyPublisher<HealthEnclaveClient, ApplicationError> {
        let client = HealthEnclaveClient(ipAddress: ipAddress, port: port, certificate: certificate, deviceIdentifier: deviceIdentifier)
        return client.establishConnection()
            .map { client }
            .eraseToAnyPublisher()
    }
    
    private init(ipAddress: String,
                 port: Int,
                 certificate: NIOSSLCertificate,
                 deviceIdentifier: DeviceCryptography.DeviceIdentifier) {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
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
        
        client = HealthEnclave_HealthEnclaveClient(channel: channel)
        self.deviceIdentifier = deviceIdentifier
    }
    
    private func establishConnection() -> AnyPublisher<Void, ApplicationError>  {
        let subject = PassthroughSubject<Void, ApplicationError>()
        var sentToSubject = false
        
        self.keepAliveCall = self.client.keepAlive(callOptions: self.callOptions()) { _ in
            if !sentToSubject {
                sentToSubject = true
                subject.send(Void())
            }
        }
        
        _ = self.keepAliveCall?.status.always { result in
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
        
        self.group.next().scheduleRepeatedAsyncTask(initialDelay: .seconds(0), delay: keepAliveInterval, { task in
            guard let keepAliveCall = self.keepAliveCall else {
                let cancelPromise: EventLoopPromise<Void> = self.group.next().makePromise()
                task.cancel(promise: cancelPromise)
                return cancelPromise.futureResult
            }
            return keepAliveCall.sendMessage(Google_Protobuf_Empty());
        })
        
        self.missingDocumentsCall = self.client.missingDocumentsForDevice(Google_Protobuf_Empty(), callOptions: self.callOptions()) { identifier in
            let documentStreamSubject = PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Error>()
            self._documentReceivedSubject.send(documentStreamSubject)
            
            let transferDocumentToDeviceCall = self.client.transferDocumentToDevice(identifier, callOptions: self.callOptions()) { documentChunked in
                documentStreamSubject.send(documentChunked)
            }
            _ = transferDocumentToDeviceCall.status.map { status in
                if status == .ok {
                    documentStreamSubject.send(completion: .finished)
                } else {
                    documentStreamSubject.send(completion: .failure(status))
                }
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    func advertiseDocumentsToTerminal(_ documentsMetadata: [HealthEnclave_DocumentMetadata]) {
        let streamingCall = client.advertiseDocumentsToTerminal(callOptions: callOptions())
        os_log(.info, "Documents: %@", String(reflecting: documentsMetadata))
        _ = streamingCall.sendMessages(documentsMetadata)
        _ = streamingCall.sendEnd()
    }
    
    func transferTwofoldEncryptedDocumentKeyToTerminal(_ twofoldEncryptedKey: HealthEnclave_TwofoldEncryptedDocumentKey,
                                                       with identifier: HealthEnclave_DocumentIdentifier) {
        _ = client.transferTwofoldEncryptedDocumentKeyToTerminal(HealthEnclave_TwofoldEncryptedDocumentKeyWithId.with({
            $0.id = identifier
            $0.key = twofoldEncryptedKey
        }), callOptions: callOptions())
    }
    
    private func callOptions() -> CallOptions {
        return CallOptions(customMetadata: [
            "deviceIdentifier": deviceIdentifier.hexEncodedString
        ])
    }
    
    func disconnect() {
        try! keepAliveCall?.sendEnd().wait()
        try! client.channel.close().wait()
        try! group.syncShutdownGracefully()
    }
}
