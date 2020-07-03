//
//  DocumentsModel.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 03.07.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import os
import Foundation
import Combine

import HealthEnclaveCommon

class DocumentsModel {
    private let deviceKey: DeviceCryptography.DeviceKey
    private let documentStore: DocumentStore
    private let client: HealthEnclaveClient
    
    private var documentReceivedSubscription: Cancellable?
    
    init(deviceKey: DeviceCryptography.DeviceKey, documentStore: DocumentStore, client: HealthEnclaveClient) {
        self.deviceKey = deviceKey
        self.documentStore = documentStore
        self.client = client
        
        documentReceivedSubscription = client.documentReceivedSubject
            .receive(on: DispatchQueue.global())
            .sink(receiveValue: { documentStreamSubject in
                var metadata: HealthEnclave_DocumentMetadata?
                
                let twofoldEncryptedDocumentStreamSubject: AnyPublisher<HealthEnclave_TwofoldEncyptedDocumentChunked, Error> = documentStreamSubject
                    .flatMap { chunk -> AnyPublisher<HealthEnclave_TwofoldEncyptedDocumentChunked, Error> in
                        switch chunk.content {
                        case let .metadata(m):
                            metadata = m
                        case let .key(key):
                            if let metadata = metadata {
                                var k: HealthEnclave_TwofoldEncryptedDocumentKey?
                                
                                switch key.content {
                                case let .onefoldEncryptedKey(onefoldEncryptedKey):
                                    k = try! DeviceCryptography.encryptEncryptedDocumentKey(onefoldEncryptedKey,
                                                                                                         using: self.deviceKey,
                                                                                                         authenticating: metadata)
                                case let .twofoldEncryptedKey(twofoldEncryptedKey):
                                    k = twofoldEncryptedKey
                                default: break
                                }
                                
                                self.client.transferTwofoldEncryptedDocumentKeyToTerminal(k!, with: metadata.id)

                                return Publishers.Sequence(sequence: [
                                    HealthEnclave_TwofoldEncyptedDocumentChunked.with {
                                        $0.metadata = metadata
                                    },
                                    HealthEnclave_TwofoldEncyptedDocumentChunked.with {
                                        $0.key = k!
                                    },
                                ]).eraseToAnyPublisher()
                            } else {
                                os_log(.error, "Receiving document failed: key received before metadata")
                            }
                        case let .chunk(chunk):
                            return Result.success(HealthEnclave_TwofoldEncyptedDocumentChunked.with {
                                $0.chunk = chunk
                            }).publisher.eraseToAnyPublisher()
                        default: break
                        }
                        return Empty().eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
                
                self.documentStore.storeDocument(from: twofoldEncryptedDocumentStreamSubject)
            })
    }
}

