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

class HealthEnclaveServer {
    private let group: EventLoopGroup
    //private var server: Server?
    
    init(ipAddress: String, port: Int, certificateChain: [NIOSSLCertificate], privateKey: NIOSSLPrivateKey) {
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        // Create a provider using the features we read.
        let provider = HealthEnclaveProvider()
        
        // Start the server and print its address once it has started.
        let server = Server.secure(group: group, certificateChain: certificateChain, privateKey: privateKey)
            .withServiceProviders([provider])
            .bind(host: ipAddress, port: port)
        
        server.whenSuccess { server in
            logger.info("Server listening on port: \(server.channel.localAddress!.port!)")
            
            let _ = server.onClose.always { _ in
                logger.info("Server closed")
            }
        }
    }
    
    deinit {
        try! group.syncShutdownGracefully()
    }
}
