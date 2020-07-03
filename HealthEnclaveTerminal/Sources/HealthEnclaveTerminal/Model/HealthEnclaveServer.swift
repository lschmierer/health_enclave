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
    
    let missingDocumentsForDeviceSubject = PassthroughSubject<HealthEnclave_DocumentIdentifier, Never>()
    private var missingDocumentsForDeviceSubscription: Cancellable?
    
    let _transferDocumentToDeviceRequestSubject =
        PassthroughSubject<(HealthEnclave_DocumentIdentifier, PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Never>), Never>();
    var transferDocumentToDeviceRequestSubject:
        AnyPublisher<(HealthEnclave_DocumentIdentifier, PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Never>), Never> {
        get { return _transferDocumentToDeviceRequestSubject.eraseToAnyPublisher() }
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
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
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
                
                return context.eventLoop.makeSucceededFuture( { event in
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
            return checkClient(context).flatMapThrowing {
                throw GRPCStatus(code: .unimplemented, message: "not implemented yet")
            }
    }
    
    
    func missingDocumentsForDevice(request: Google_Protobuf_Empty,
                                   context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMap {
                let promise = context.eventLoop.makePromise(of: GRPCStatus.self)
                
                self.missingDocumentsForDeviceSubscription = self.missingDocumentsForDeviceSubject
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
            return checkClient(context).flatMapThrowing {
                throw GRPCStatus(code: .unimplemented, message: "not implemented yet")
            }
    }
    
    func missingEncryptedDocumentKeysForTerminal(request: Google_Protobuf_Empty,
                                                 context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMapThrowing {
                throw GRPCStatus(code: .unimplemented, message: "not implemented yet")
            }
    }
    
    func missingTwofoldEncryptedDocumentKeysForTerminal(request: Google_Protobuf_Empty,
                                                        context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMapThrowing {
                throw GRPCStatus(code: .unimplemented, message: "not implemented yet")
            }
    }
    
    func transferDocumentToDevice(request: HealthEnclave_DocumentIdentifier,
                                  context: StreamingResponseCallContext<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked>)
        -> EventLoopFuture<GRPCStatus> {
            return checkClient(context).flatMap {
                let promise = context.eventLoop.makePromise(of: GRPCStatus.self)
                
                let documentStreamSubject = PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Never>()
                
                let documentStreamSubscription = documentStreamSubject.sink(
                    receiveCompletion: { _ in
                        promise.succeed(.ok)
                }) { chunk in
                    _ = context.sendResponse(chunk)
                }
                
                self._transferDocumentToDeviceRequestSubject
                    .send((request, documentStreamSubject))
                
                return promise.futureResult.always { _ in
                    documentStreamSubscription.cancel()
                }
            }
    }
    
    func transferDocumentToTerminal(request: HealthEnclave_TwofoldEncyptedDocumentChunked,
                                    context: StatusOnlyCallContext)
        -> EventLoopFuture<Google_Protobuf_Empty> {
            return checkClient(context).flatMapThrowing {
                throw GRPCStatus(code: .unimplemented, message: "not implemented yet")
            }
    }
    
    func transferEncryptedDocumentKeyToTerminal(request: HealthEnclave_EncryptedDocumentKeyWithId,
                                                context: StatusOnlyCallContext)
        -> EventLoopFuture<Google_Protobuf_Empty> {
            return checkClient(context).flatMapThrowing {
                throw GRPCStatus(code: .unimplemented, message: "not implemented yet")
            }
    }
    
    func transferTwofoldEncryptedDocumentKeyToTerminal(request: HealthEnclave_TwofoldEncryptedDocumentKeyWithId,
                                                       context: StatusOnlyCallContext)
        -> EventLoopFuture<Google_Protobuf_Empty> {
            return checkClient(context).map {
                self._twofoldEncryptedDocumentKeySubject.send(request)
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
        missingDocumentsForDeviceSubject.send(completion: .finished)
        missingDocumentsForDeviceSubscription?.cancel()
        try! server?.close().wait()
        try! group.syncShutdownGracefully()
    }
}
