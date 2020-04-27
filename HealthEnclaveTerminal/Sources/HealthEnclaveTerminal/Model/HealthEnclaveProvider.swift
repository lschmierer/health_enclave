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
    func documentRequests(context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>) -> EventLoopFuture<(StreamEvent<HealthEnclave_DocumentIdentifier>) -> Void> {
        return context.eventLoop.makeSucceededFuture({ event in
            switch event {
            case .message(let documentIdentifier):
                _ = context.sendResponse(documentIdentifier)
                
            case .end:
                context.statusPromise.succeed(.ok)
            }
        })
    }
    
    func documentRequests2(context: StreamingResponseCallContext<HealthEnclave_DocumentIdentifier>) -> EventLoopFuture<(StreamEvent<HealthEnclave_DocumentIdentifier>) -> Void> {
        return documentRequests(context: context);
    }
    
}
