//
//  HealthEnclaveClient.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 04.04.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import Dispatch
import GRPC
import NIO
import NIOSSL

import HealthEnclaveCommon

class HealthEnclaveClient: ConnectivityStateDelegate {
    
    private var connectionCallback: ApplicationModel.ConnectionCallback?
    
    private let group: EventLoopGroup
    private var client: HealthEnclave_HealthEnclaveClient!
    
    init(ipAddress: String,
         port: Int,
         certificate: NIOSSLCertificate,
         onConnection connectionCallback: @escaping ApplicationModel.ConnectionCallback) {
        self.connectionCallback = connectionCallback
        
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        let configuration = ClientConnection.Configuration(
            target: .hostAndPort(ipAddress, port),
            eventLoopGroup: group,
            connectivityStateDelegate: self,
            tls: ClientConnection.Configuration.TLS(
                trustRoots: .certificates([certificate]),
                certificateVerification: .noHostnameVerification),
            // In this local setup, TLS conenction is expected to work on first try.
            connectionBackoff: nil
        )
        let channel = ClientConnection(configuration: configuration)
        
        client = HealthEnclave_HealthEnclaveClient(channel: channel)
    }
    
    func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
        if let connectionCallback = connectionCallback {
            if(newState == .ready) {
                DispatchQueue.main.async {
                    connectionCallback(.success(()))
                }
                self.connectionCallback = nil
            } else if(newState == .shutdown) {
                DispatchQueue.main.async {
                    connectionCallback(.failure(.connection))
                }
                self.connectionCallback = nil
            }
        }
    }
    
    func establishConnection() {
        let call = client.documentRequests { documentIdentifier in
            debugPrint(documentIdentifier)
        }
        
        call.status.always { result in
            debugPrint(result)
        }
        
        let _ = call.sendMessage(HealthEnclave_DocumentIdentifier.with { $0.uuid = "1" })
        
    }
    
    deinit {
        let _ = client.channel.close()
        try! group.syncShutdownGracefully()
    }
}
