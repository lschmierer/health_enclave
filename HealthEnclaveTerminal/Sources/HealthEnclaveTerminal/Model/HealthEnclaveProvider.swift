//
//  HealthEnclaveProvider.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 03.04.20.
//
import GRPC
import NIO

import HealthEnclaveCommon


class HealthEnclaveProvider: HealthEnclave_HealthEnclaveProvider {    
    func sayHello(request: HealthEnclave_HelloRequest, context: StatusOnlyCallContext) -> EventLoopFuture<HealthEnclave_HelloReply> {
        
        return context.eventLoop.makeSucceededFuture(HealthEnclave_HelloReply.with {
            $0.message = "Hello \(request.name)"
        })
    }
}
