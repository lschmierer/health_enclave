//
//  HealthEnclaveClient.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 04.04.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import Foundation
import os
import Dispatch
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
    private let group: EventLoopGroup
    private var client: HealthEnclave_HealthEnclaveClient
    private let deviceIdentifier: HealthEnclave_DeviceIdentifier
    private var keepAliveCall: BidirectionalStreamingCall<SwiftProtobuf.Google_Protobuf_Empty, SwiftProtobuf.Google_Protobuf_Empty>?
    
    init(ipAddress: String,
         port: Int,
         certificate: NIOSSLCertificate,
         deviceIdentifier: HealthEnclave_DeviceIdentifier) {
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
    
    func establishConnection(onConnect connectionCallback: @escaping ApplicationModel.ConnectionCallback) {
        keepAliveCall = client.keepAlive(callOptions: callOptions()) { _ in
            DispatchQueue.main.async {
                connectionCallback(.success(()))
            }
        }
        
        let _ = keepAliveCall?.status.always { result in
            os_log(.error, "KeepAlive status: %@", String(reflecting: result))
            guard case let .success(status) = result, status.code == .ok else {
                DispatchQueue.main.async {
                    switch result {
                    case .success(let status):
                        let error = ApplicationError.connection(status.message)
                        connectionCallback(.failure(error))
                    case .failure(let error):
                        connectionCallback(.failure(.connection(error)))
                    }
                }
                return
            }
        }
        
        
        group.next().scheduleRepeatedAsyncTask(initialDelay: .seconds(0), delay: keepAliveInterval, { task in
            guard let keepAliveCall = self.keepAliveCall else {
                let cancelPromise: EventLoopPromise<Void> = self.group.next().makePromise()
                task.cancel(promise: cancelPromise)
                return cancelPromise.futureResult
            }
            return keepAliveCall.sendMessage(Google_Protobuf_Empty());
        })
    }
    
    private func callOptions() -> CallOptions {
        return CallOptions(customMetadata: [
            "deviceIdentifier": try! deviceIdentifier.jsonString()
        ])
    }
    
    func disconnect() {
        try! keepAliveCall?.sendEnd().wait()
        try! client.channel.close().wait()
        try! group.syncShutdownGracefully()
    }
}
