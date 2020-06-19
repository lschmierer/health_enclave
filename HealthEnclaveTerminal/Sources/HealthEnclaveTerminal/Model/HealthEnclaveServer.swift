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
    
    func makeGRPCStatus() -> GRPCStatus {
        switch self {
        case .clientAlreadyConnected:
            return GRPCStatus(code: .resourceExhausted, message: "another client is already connected")
        case .clientTimedOut:
            return GRPCStatus(code: .unavailable, message: "client timed out")
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
    
    private let group: EventLoopGroup
    private var server: Server?
    
    private var clientConnected: Bool = false
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
    
    func keepAlive(context: StreamingResponseCallContext<SwiftProtobuf.Google_Protobuf_Empty>) -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
        
        if (!clientConnected) {
            logger.info("Client connected")
            _deviceConnectedSubject.send()
            clientConnected = true
            
            return context.eventLoop.makeSucceededFuture( { [weak self] event in
                guard let self = self else { return }
                
                switch event {
                case .message(let msg):
                    self.lastKeepAlive = Date()
                    self.group.next().scheduleTask(in: keepAliveTimeout, {
                        let timeInterval = TimeInterval(keepAliveTimeout.nanoseconds / (1000 * 1000 * 1000))
                        if self.clientConnected, Date() > self.lastKeepAlive + timeInterval {
                            logger.info("Client connection lost")
                            
                            self.clientConnected = false
                            context.statusPromise.fail(ServerError.clientTimedOut)                       }
                    })
                    
                    _ = context.sendResponse(msg)
                    
                case .end:
                    logger.info("Client disconnected")
                    self._deviceConnectionLostSubject.send()
                    self.clientConnected = false
                    context.statusPromise.succeed(.ok)
                }
            })
        } else {
            return context.eventLoop.makeFailedFuture(ServerError.clientAlreadyConnected)
        }
    }
    
    func advertiseDocumentsToTerminal(context: UnaryResponseCallContext<Google_Protobuf_Empty>) -> EventLoopFuture<(StreamEvent<HealthEnclave_DocumentMetadata>) -> Void> {
        return context.eventLoop.makeSucceededFuture({ _ in
            context.responsePromise.fail(GRPCStatus(code: .unimplemented, message: "not implemented yet"))
        })
    }
    
    func missingDocumentsForDevice(request: Google_Protobuf_Empty, context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>) -> EventLoopFuture<GRPCStatus> {
        return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented, message: "not implemented yet"))
    }
    
    func missingDocumentsForTerminal(request: Google_Protobuf_Empty, context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>) -> EventLoopFuture<GRPCStatus> {
        return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented, message: "not implemented yet"))
    }
    
    func missingDocumentKeysForTerminal(request: Google_Protobuf_Empty, context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>) -> EventLoopFuture<GRPCStatus> {
        return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented, message: "not implemented yet"))
    }
    
    func transferDocumentToDevice(request: HealthEnclave_DocumentIdentifier, context: StreamingResponseCallContext<HealthEnclave_OneOrTwofoldEncyptedDocumentChunk>) -> EventLoopFuture<GRPCStatus> {
        return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented, message: "not implemented yet"))
    }
    
    func transferDocumentToTerminal(request: HealthEnclave_TwofoldEncryptedDocumentChunk, context: StatusOnlyCallContext) -> EventLoopFuture<Google_Protobuf_Empty> {
        return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented, message: "not implemented yet"))
    }
    
    func transferDocumentKeyToTerminal(request: HealthEnclave_EncryptedDocumentKeyWithId, context: StatusOnlyCallContext) -> EventLoopFuture<Google_Protobuf_Empty> {
        return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented, message: "not implemented yet"))
    }
    
    func close() {
        try! server?.close().wait()
        try! group.syncShutdownGracefully()
    }
}
