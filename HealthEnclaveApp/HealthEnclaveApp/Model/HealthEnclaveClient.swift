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
    typealias ConnectionCallback = (_ result: Result<Void, Error>) -> Void
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
        self.connectionErrorCallback = connectionErrorCallback
    }
    
    func handleConnectionError<T>(_ result: Result<T,Error>) {
        if case let .failure(error) = result {
            DispatchQueue.main.async {
                self.connectionErrorCallback(error)
            }
        }
    }
    
    func establishConnection(onConnection connectionCallback: @escaping ConnectionCallback) {
        let _ = client.sayHello(HealthEnclave_HelloRequest.with { $0.name = "Client" }).response
            .always { self.handleConnectionError($0) }
            .always { result in DispatchQueue.main.async { connectionCallback(result.map {_ in () }) } }
            .always { result in
                print(result)
        }
    }
    
    deinit {
        let _ = client.channel.close()
        try! group.syncShutdownGracefully()
    }
}
