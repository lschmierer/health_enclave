//
//  HealthEnclaveServer.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 03.04.20.
//
import Foundation
import SwiftProtobuf
import GRPC
import NIO
import NIOSSL
import Logging

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
    private let group: EventLoopGroup
    var clientConnected: Bool = false
    var lastKeepAlive: Date!
    
    init(ipAddress: String, port: Int, certificateChain: [NIOSSLCertificate], privateKey: NIOSSLPrivateKey) {
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        // Start the server and print its address once it has started.
        let server = Server.secure(group: group, certificateChain: certificateChain, privateKey: privateKey)
            .withServiceProviders([self])
            .bind(host: ipAddress, port: port)
        
        server.whenSuccess { server in
            logger.info("Server listening on port: \(server.channel.localAddress!.port!)")
            
            let _ = server.onClose.always { _ in
                logger.info("Server closed")
            }
        }
    }
    
    func keepAlive(context: StreamingResponseCallContext<SwiftProtobuf.Google_Protobuf_Empty>) -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
        
        if (!clientConnected) {
            logger.info("Client connected")
            clientConnected = true
            
            return context.eventLoop.makeSucceededFuture({ event in
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
    
    deinit {
        try! group.syncShutdownGracefully()
    }
}
