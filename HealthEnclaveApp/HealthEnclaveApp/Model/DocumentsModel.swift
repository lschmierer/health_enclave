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
    private let _accessDocumentRequests = PassthroughSubject<HealthEnclave_DocumentMetadata, Never>()
    var accessDocumentRequests: AnyPublisher<HealthEnclave_DocumentMetadata, Never> {
        get { return _accessDocumentRequests.eraseToAnyPublisher() }
    }
    
    private let deviceKey: DeviceCryptography.DeviceKey
    private weak var documentStore: DocumentStore?
    private weak var client: HealthEnclaveClient?
    
    private var missingDocumentsForTerminal = [HealthEnclave_DocumentIdentifier]()
    private var transferringToTerminal = false
    private var transferToTerminalSubscription: Cancellable?
    
    private var missingDocumentsForDeviceSubscription: Cancellable?
    private var missingDocumentsForTerminalSubscription: Cancellable?
    private var missingEncryptedDocumentKeyForTermincalSubscription: Cancellable?
    private var missingTwofoldEncryptedDocumentKeyForTermincalSubscription: Cancellable?
    
    init(deviceKey: DeviceCryptography.DeviceKey, documentStore: DocumentStore, client: HealthEnclaveClient) {
        self.deviceKey = deviceKey
        self.documentStore = documentStore
        self.client = client
        
        setupMissingDocumentsForDeviceSubscription()
        setupMissingDocumentsForTerminalSubscription()
        setupMissingEncryptedDocumentKeyForTerminalSubscription()
        
        client.advertiseDocmentsToTerminal(documentStore.allDocumentsMetadata())
    }
    
    func grantAccess(to documentIdentifier: HealthEnclave_DocumentIdentifier) {
        if let twofoldEncyptedKey = try! documentStore?.twofoldEncryptedDocumentKey(with: documentIdentifier),
           let documentMetadata = documentStore?.metadata(for: documentIdentifier) {
            let encryptedKey = try! DeviceCryptography.decryptTwofoldEncryptedDocumentKey(twofoldEncyptedKey, using: self.deviceKey, authenticating: documentMetadata)
            
            self.client?.transferEncryptedDocumentKeyToTerminal(encryptedKey, with: documentIdentifier)
        } else {
            os_log(.error, "Can not find key for document with id: %@", documentIdentifier.uuid)
        }
    }
    
    func grantAccessNot(to documentIdentifier: HealthEnclave_DocumentIdentifier) {
        self.client?.transferEncryptedDocumentKeyNotToTerminal(for: documentIdentifier)
    }
    
    private func setupMissingDocumentsForDeviceSubscription() {
        missingDocumentsForDeviceSubscription = client?.missingDocumentsForDeviceSubject
            .receive(on: DispatchQueue.global())
            .sink(receiveValue: { [weak self] documentIdentifier in
                guard let self = self, let client = self.client, let documentStore = self.documentStore else { return }
                
                var metadata: HealthEnclave_DocumentMetadata?
                
                let twofoldEncryptedDocumentStreamSubject: AnyPublisher<HealthEnclave_TwofoldEncyptedDocumentChunked, Error> = client.transferDocumentsToDevice(with: documentIdentifier)
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
                                
                                client.transferTwofoldEncryptedDocumentKeyToTerminal(k!, with: metadata.id)
                                
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
                    .buffer(size: .max, prefetch: .keepFull, whenFull: .dropNewest)
                    .eraseToAnyPublisher()
                
                documentStore.storeDocument(from: twofoldEncryptedDocumentStreamSubject)
            })
    }
    
    private func setupMissingDocumentsForTerminalSubscription() {
        missingDocumentsForTerminalSubscription = client?.missingDocumentsForTerminalSubject
            .receive(on: DispatchQueue.global())
            .sink(receiveValue: { [weak self] documentIdentifier in
                guard let self = self else { return }
                
                if let index = self.missingDocumentsForTerminal.firstIndex(of: documentIdentifier) {
                    self.missingDocumentsForTerminal.remove(at: index)
                }
                self.missingDocumentsForTerminal.append(documentIdentifier)
                
                self.transferToTerminal()
            })
    }
    
    private func transferToTerminal() {
        guard let documentStore = documentStore,
              !transferringToTerminal else { return }
        
        if let documentIdentifier = missingDocumentsForTerminal.popLast() {
            transferringToTerminal = true
            
            self.client?.transferEncryptedDocumentToTerminal(chunks: try! documentStore.encryptedDocumentChunked(for: documentIdentifier))
            
            self.transferringToTerminal = false
            self.transferToTerminal()
        }
    }
    
    private func setupMissingEncryptedDocumentKeyForTerminalSubscription() {
        missingEncryptedDocumentKeyForTermincalSubscription = client?.missingEncryptedDocumentKeyForTerminalSubject
            .receive(on: DispatchQueue.global())
            .sink(receiveValue: { [weak self] documentIdentifier in
                guard let self = self, let documentStore = self.documentStore else { return }
                
                if let documentMetadata = documentStore.metadata(for: documentIdentifier) {
                    self._accessDocumentRequests.send(documentMetadata)
                } else {
                    os_log(.error, "Can not find key for document with id: %@", documentIdentifier.uuid)
                }
            })
    }
}

