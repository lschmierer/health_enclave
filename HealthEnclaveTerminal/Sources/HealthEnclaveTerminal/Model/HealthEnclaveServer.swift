//
//  HealthEnclaveServer.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 03.04.20.
//
import Foundation
import GRPC
import NIO
import NIOSSL
import Logging

import HealthEnclaveCommon

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.HealthEnclaveServer")

enum ServerError: Error {
    // Another client is already connected
    case clientAlreadyConnected
}

class HealthEnclaveServer: HealthEnclave_HealthEnclaveProvider {
    private let group: EventLoopGroup
    var clientConnected: Bool = false
    
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
    
    func documentRequests(context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>) -> EventLoopFuture<(StreamEvent<HealthEnclave_DocumentIdentifier>) -> Void> {
        
        if (!clientConnected) {
            clientConnected = true
            
            return context.eventLoop.makeSucceededFuture({ event in
                switch event {
                case .message(let documentIdentifier):
                    _ = context.sendResponse(documentIdentifier)
                    
                case .end:
                    clientConnected = false
                    context.statusPromise.succeed(.ok)
                }
            })
        } else {
            return context.eventLoop.makeSucceededFuture({ _ in
                context.statusPromise.fail(ServerError.clientAlreadyConnected)
            })
        }
    }
    
    deinit {
        try! group.syncShutdownGracefully()
    }
}
