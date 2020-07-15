//
//  HealthEnclaveServer.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 03.04.20.
//
import Foundation
import Logging
import SwiftProtobuf
import GRPC
import NIO
import NIOSSL

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

import HealthEnclaveCommon

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.HealthEnclaveServer")

private let keepAliveTimeout: TimeAmount = .seconds(2)

enum ServerError: Error, GRPCStatusTransformable {
    
    // Another client is already connected
    case clientAlreadyConnected
    
    // Client timed out
    case clientTimedOut
    
    // Client timed out
    case clientInvalidIdentifier
    
    func makeGRPCStatus() -> GRPCStatus {
        switch self {
        case .clientAlreadyConnected:
            return GRPCStatus(code: .resourceExhausted, message: "another client is already connected")
        case .clientTimedOut:
            return GRPCStatus(code: .unavailable, message: "client timed out")
        case .clientInvalidIdentifier:
            return GRPCStatus(code: .invalidArgument, message: "no or invalid device identifier")
        }
        
    }
}

class HealthEnclaveServer: HealthEnclave_HealthEnclaveProvider {
    private let _deviceConnectedSubject = PassthroughSubject<Void, Never>()
    var deviceConnectedSubject: AnyPublisher<Void, Never> {
        get { return _deviceConnectedSubject.eraseToAnyPublisher() }
    }
    
    private let _deviceConnectionLostSubject = PassthroughSubject<Void, Never>()
    var deviceConnectionLostSubject: AnyPublisher<Void, Never> {
        get { return _deviceConnectionLostSubject.eraseToAnyPublisher() }
    }
    
    private let _deviceAdvertisedDocumentsSubject = PassthroughSubject<HealthEnclave_DocumentMetadata, Never>();
    var deviceAdvertisedDocumentsSubject: AnyPublisher<HealthEnclave_DocumentMetadata, Never> {
        get { return _deviceAdvertisedDocumentsSubject.eraseToAnyPublisher() }
    }
    
    let missingDocumentsForDeviceSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never>()
    private var missingDocumentsForDeviceSubscription: Cancellable?
    
    let missingDocumentsForTerminalSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never>()
    private var missingDocumentsForTerminalSubscription: Cancellable?
    
    let missingEncryptedDocumentKeysForTerminalSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never> ()
    private var missingEncryptedDocumentKeysForTerminalSubscription: Cancellable?
    
    let missingTwofoldEncryptedDocumentKeysForTerminalSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never> ()
    private var missingTwofoldEncryptedDocumentKeysForTerminalSubscription: Cancellable?
    
    private let _transferDocumentToDeviceRequestSubject =
        PassthroughSubject<(HealthEnclave_DocumentIdentifier, PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Never>), Never>();
    var transferDocumentToDeviceRequestSubject:
        AnyPublisher<(HealthEnclave_DocumentIdentifier, PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Never>), Never> {
        get { return _transferDocumentToDeviceRequestSubject.eraseToAnyPublisher() }
    }
    
    private let _documentSubject = PassthroughSubject<AnyPublisher<HealthEnclave_TwofoldEncyptedDocumentChunked, Never>, Never>()
    var documentSubject: AnyPublisher<AnyPublisher<HealthEnclave_TwofoldEncyptedDocumentChunked, Never>, Never> {
        get { return _documentSubject.eraseToAnyPublisher() }
    }
    
    private let _encryptedDocumentKeySubject = PassthroughSubject<HealthEnclave_EncryptedDocumentKeyWithId, Never>()
    var encryptedDocumentKeySubject: AnyPublisher<HealthEnclave_EncryptedDocumentKeyWithId, Never> {
        get { return _encryptedDocumentKeySubject.eraseToAnyPublisher() }
    }
    
    private let _twofoldEncryptedDocumentKeySubject = PassthroughSubject<HealthEnclave_TwofoldEncryptedDocumentKeyWithId, Never>()
    var twofoldEncryptedDocumentKeySubject: AnyPublisher<HealthEnclave_TwofoldEncryptedDocumentKeyWithId, Never> {
        get { return _twofoldEncryptedDocumentKeySubject.eraseToAnyPublisher() }
    }
    
    private let group: EventLoopGroup
    private var server: Server?
    
    private(set) var connectedDevice: DeviceCryptography.DeviceIdentifier?
    private var lastKeepAlive: Date!
    
    init(ipAddress: String, port: Int, certificateChain: [NIOSSLCertificate], privateKey: NIOSSLPrivateKey) {
        group = PlatformSupport.makeEventLoopGroup(loopCount: System.coreCount)
        // Start the server and print its address once it has started.
        let server = Server.secure(group: group, certificateChain: certificateChain, privateKey: privateKey)
            .withServiceProviders([self])
            .bind(host: ipAddress, port: port)
        
        server.whenSuccess { [weak self] server in
            logger.info("Server listening on port: \(server.channel.localAddress!.port!)")
            
            self?.server = server
            
            let _ = server.onClose.always { _ in
                logger.info("Server closed")
            }
        }
    }
    
    func keepAlive(context: StreamingResponseCallContext<SwiftProtobuf.Google_Protobuf_Empty>)
        -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
            if (connectedDevice == nil) {
                let deviceIdentifierHeaders = context.request.headers["deviceIdentifier"]
                guard !deviceIdentifierHeaders.isEmpty else {
                    logger.error("Client sent no identifier")
                    return context.eventLoop.makeFailedFuture(ServerError.clientInvalidIdentifier)
                }
                
                guard let connectedDevice =  DeviceCryptography.DeviceIdentifier(hexEncoded: deviceIdentifierHeaders[0]) else {
                    logger.error("Client sent invalid identifier")
                    return context.eventLoop.makeFailedFuture(ServerError.clientInvalidIdentifier)
                }
                self.connectedDevice = connectedDevice
                
                logger.info("Client connected")
                
                _deviceConnectedSubject.send()
                
                return context.eventLoop.makeSucceededFuture( { [weak self] event in
                    guard let self = self else { return }
                    switch event {
                    case .message(let msg):
                        self.lastKeepAlive = Date()
                        self.group.next().scheduleTask(in: keepAliveTimeout, {
                            let timeInterval = TimeInterval(keepAliveTimeout.nanoseconds / (1000 * 1000 * 1000))
                            if self.connectedDevice != nil,
                                Date() > self.lastKeepAlive + timeInterval {
                                logger.info("Client connection lost")
                                self._deviceConnectionLostSubject.send()
                                self.connectedDevice = nil
                                context.statusPromise.fail(ServerError.clientTimedOut)                       }
                        })
                        
                        _ = context.sendResponse(msg)
                        
                    case .end:
                        logger.info("Client disconnected")
                        self._deviceConnectionLostSubject.send()
                        self.connectedDevice = nil
                        context.statusPromise.succeed(.ok)
                    }
                })
            } else {
                return context.eventLoop.makeFailedFuture(ServerError.clientAlreadyConnected)
            }
    }
    
    func advertiseDocumentsToTerminal(context: UnaryResponseCallContext<Google_Protobuf_Empty>)
        -> EventLoopFuture<(StreamEvent<HealthEnclave_DocumentMetadata>) -> Void> {
            return checkClient(context).map { [weak self] in
                return { event in
                    guard let self = self else { return }
                    if case let .message(metadata) = event {
                        self._deviceAdvertisedDocumentsSubject.send(metadata)
                    }
                }
            }
    }
    
    
    func missingDocumentsForDevice(request: Google_Protobuf_Empty,
                                   context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMap { [weak self] in
                let promise = context.eventLoop.makePromise(of: GRPCStatus.self)
                
                self?.missingDocumentsForDeviceSubscription = self?.missingDocumentsForDeviceSubject
                    .sink(
                        receiveCompletion: {_ in
                            promise.succeed(.ok)
                    }, receiveValue: { documentIdentifier in
                        _ = context.sendResponse(documentIdentifier)
                    })
                
                return promise.futureResult
            }
    }
    
    func missingDocumentsForTerminal(request: Google_Protobuf_Empty,
                                     context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMap { [weak self] in
                let promise = context.eventLoop.makePromise(of: GRPCStatus.self)
                
                self?.missingDocumentsForTerminalSubscription = self?.missingDocumentsForTerminalSubject
                    .sink(
                        receiveCompletion: {_ in
                            promise.succeed(.ok)
                    }, receiveValue: { documentIdentifier in
                        _ = context.sendResponse(documentIdentifier)
                    })
                
                return promise.futureResult
            }
    }
    
    func missingEncryptedDocumentKeysForTerminal(request: Google_Protobuf_Empty,
                                                 context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMap { [weak self] in
                let promise = context.eventLoop.makePromise(of: GRPCStatus.self)
                
                self?.missingEncryptedDocumentKeysForTerminalSubscription = self?.missingEncryptedDocumentKeysForTerminalSubject
                    .sink(
                        receiveCompletion: {_ in
                            promise.succeed(.ok)
                    }, receiveValue: { documentIdentifier in
                        _ = context.sendResponse(documentIdentifier)
                    })
                
                return promise.futureResult
            }
    }
    
    func missingTwofoldEncryptedDocumentKeysForTerminal(request: Google_Protobuf_Empty,
                                                        context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMap { [weak self] in
                let promise = context.eventLoop.makePromise(of: GRPCStatus.self)
                
                self?.missingTwofoldEncryptedDocumentKeysForTerminalSubscription = self?.missingTwofoldEncryptedDocumentKeysForTerminalSubject
                    .sink(
                        receiveCompletion: {_ in
                            promise.succeed(.ok)
                    }, receiveValue: { documentIdentifier in
                        _ = context.sendResponse(documentIdentifier)
                    })
                
                return promise.futureResult
            }
    }
    
    func transferDocumentToDevice(request: HealthEnclave_DocumentIdentifier,
                                  context: StreamingResponseCallContext<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMap { [weak self] in
                let promise = context.eventLoop.makePromise(of: GRPCStatus.self)
                
                let documentStreamSubject = PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Never>()
                
                let documentStreamSubscription = documentStreamSubject.sink(
                    receiveCompletion: { _ in
                        promise.succeed(.ok)
                }) { chunk in
                    _ = context.sendResponse(chunk)
                }
                
                self?._transferDocumentToDeviceRequestSubject
                    .send((request, documentStreamSubject))
                
                return promise.futureResult.always { _ in
                    documentStreamSubscription.cancel()
                }
            }
    }
    
    func transferDocumentToTerminal(context: UnaryResponseCallContext<Google_Protobuf_Empty>)
        -> EventLoopFuture<(StreamEvent<HealthEnclave_TwofoldEncyptedDocumentChunked>) -> Void> {
            return checkClient(context).map { [weak self] in
                let documentStreamSubject = PassthroughSubject<HealthEnclave_TwofoldEncyptedDocumentChunked, Never>()
                
                self?._documentSubject.send(documentStreamSubject.eraseToAnyPublisher())
                
                return { event in
                    switch event {
                    case let .message(chunk):
                        documentStreamSubject.send(chunk)
                    case .end:
                        documentStreamSubject.send(completion: .finished)
                    }
                }
            }
    }
    
    func transferEncryptedDocumentKeyToTerminal(request: HealthEnclave_EncryptedDocumentKeyWithId,
                                                context: StatusOnlyCallContext)
        -> EventLoopFuture<Google_Protobuf_Empty> {
            return checkClient(context).map { [weak self] in
                self?._encryptedDocumentKeySubject.send(request)
                return Google_Protobuf_Empty()
            }
    }
    
    func transferTwofoldEncryptedDocumentKeyToTerminal(request: HealthEnclave_TwofoldEncryptedDocumentKeyWithId,
                                                       context: StatusOnlyCallContext)
        -> EventLoopFuture<Google_Protobuf_Empty> {
            return checkClient(context).map { [weak self] in
                self?._twofoldEncryptedDocumentKeySubject.send(request)
                return Google_Protobuf_Empty()
            }
    }
    
    func checkClient(_ context: ServerCallContext) -> EventLoopFuture<Void> {
        let deviceIdentifierHeaders = context.request.headers["deviceIdentifier"]
        guard !deviceIdentifierHeaders.isEmpty else {
            logger.error("Client sent no identifier")
            return context.eventLoop.makeFailedFuture(ServerError.clientInvalidIdentifier)
        }
        
        do {
            let deviceIdentifier = DeviceCryptography.DeviceIdentifier(hexEncoded: deviceIdentifierHeaders[0])
            if deviceIdentifier != connectedDevice {
                throw ServerError.clientInvalidIdentifier
            }
            return context.eventLoop.makeSucceededFuture(Void())
        } catch {
            logger.error("Client sent invalid identifier")
            return context.eventLoop.makeFailedFuture(ServerError.clientInvalidIdentifier)
        }
    }
    
    func close() {
        missingDocumentsForDeviceSubscription?.cancel()
        missingDocumentsForTerminalSubscription?.cancel()
        missingEncryptedDocumentKeysForTerminalSubscription?.cancel()
        missingTwofoldEncryptedDocumentKeysForTerminalSubscription?.cancel()
        try! server?.close().wait()
        try! group.syncShutdownGracefully()
    }
}
