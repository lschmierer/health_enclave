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


class HealthEnclaveClient {
    typealias ConnectionErrorCallback = (_ error: Error) -> Void
    
    private let group: EventLoopGroup
    private let client: HealthEnclave_HealthEnclaveClient
    private let connectionErrorCallback: ConnectionErrorCallback
    
    init(ipAddress: String, port: Int, certificate: NIOSSLCertificate, onConnectionError connectionErrorCallback: @escaping ConnectionErrorCallback) {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        let configuration = ClientConnection.Configuration(
            target: .hostAndPort(ipAddress, port),
            eventLoopGroup: group,
            tls: ClientConnection.Configuration.TLS(
                trustRoots: .certificates([certificate]),
                certificateVerification: .noHostnameVerification),
            connectionBackoff: nil
        )
        let channel = ClientConnection(configuration: configuration)
        
        client = HealthEnclave_HealthEnclaveClient(channel: channel)
        self.connectionErrorCallback = { error in
            DispatchQueue.main.async {
                connectionErrorCallback(error)
            }
        }
    }
    
    func connect() -> EventLoopFuture<Void> {
        return client.sayHello(HealthEnclave_HelloRequest.with { $0.name = "Client" }).response.always { result in
            if case let .failure(error) = result {
                self.connectionErrorCallback(error)
            }
            print(result)
        }
        .map { _ in }
    }
    
    deinit {
        let _ = client.channel.close()
        try! group.syncShutdownGracefully()
    }
}
