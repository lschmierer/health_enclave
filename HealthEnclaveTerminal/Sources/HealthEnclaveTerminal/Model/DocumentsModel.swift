//
//  DocumentsModel.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 17.06.20.
//

import Foundation
import Logging
import SwiftProtobuf

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

import HealthEnclaveCommon

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.DeviceDocumentsModel")

class DocumentsModel {
    
    private var sharedKey: TerminalCryptography.SharedKey?
    private let documentStore: DocumentStore
    private let server: HealthEnclaveServer
    
    private var _documentsMetadata = Set<HealthEnclave_DocumentMetadata>()
    var documentsMetadata: [HealthEnclave_DocumentMetadata] {
        get { return Array(_documentsMetadata) }
    }
    
    private let _documentAddedSubject = PassthroughSubject<HealthEnclave_DocumentMetadata, Never>()
    var documentAddedSubject: AnyPublisher<HealthEnclave_DocumentMetadata, Never> {
        get { return _documentAddedSubject.eraseToAnyPublisher() }
    }
    
    private var retrieveDocumentSubject: PassthroughSubject<URL, Never>?
    private var retrieveDocumentIdentifier: HealthEnclave_DocumentIdentifier?
    private var retrieveDocumentMetadata: HealthEnclave_DocumentMetadata?
    private var retrieveDocumentKey: HealthEnclave_EncryptedDocumentKey?
    private var retrieveDocumentData: Data?
    
    private var deviceAdvertisedDocumentsSubscription: Cancellable?
    private var transferDocumentToDeviceRequestSubscription: Cancellable?
    private var documentSubscription: Cancellable?
    private var documentStreamSubscriptions = Set<AnyCancellable>()
    private var encryptedDocumentKeySubscription: Cancellable?
    private var twofoldEncryptedDocumentKeySubscription: Cancellable?
    
    init(documentStore: DocumentStore, server: HealthEnclaveServer) {
        self.documentStore = documentStore
        self.server = server
        
        setupDeviceAdvertisedDocumentsSubscription()
        setupTransferDocumentToDeviceRequestSubscription()
        setupDocumentSubscription()
        setupEncryptedDocumentKeySubscription()
        setupTwofoldEncryptedDocumentKeySubscription()
    }
    
    func setSharedKey(_ sharedKey: TerminalCryptography.SharedKey) {
        self.sharedKey = sharedKey
    }
    
    func addDocumentToDevice(file: URL) throws {
        guard let sharedKey = sharedKey else {
            throw ApplicationError.missingSharedKey
        }
        
        let documentIdentifier = HealthEnclave_DocumentIdentifier.with {
            $0.uuid = UUID().uuidString
        }
        let documentMetadata = HealthEnclave_DocumentMetadata.with {
            $0.id = documentIdentifier
            $0.name = file.lastPathComponent
            $0.createdAt = Google_Protobuf_Timestamp(date: Date())
            $0.createdBy = UserDefaults.standard.string(forKey: "practitioner")!
        }
        
        let data = try Data(contentsOf: file)
        
        let (encryptedDocumentKey, encryptedDocument) = try! TerminalCryptography.encryptDocument(
            data,
            using: sharedKey,
            authenticating: documentMetadata)
        
        try documentStore.addNewEncryptedDocument(encryptedDocument, with: documentMetadata, encryptedWith: encryptedDocumentKey)
        
        server.missingDocumentsForDeviceSubject.send(documentIdentifier)
        _documentAddedSubject.send(documentMetadata)
    }
    
    func retrieveDocument(_ documentIdentifier: HealthEnclave_DocumentIdentifier) throws -> AnyPublisher<URL, Never> {
        if let retrieveDocumentSubject = retrieveDocumentSubject {
            retrieveDocumentSubject.send(completion: .finished)
        }
        
        let retrieveDocumentSubject = PassthroughSubject<URL, Never>()
        
        if let (documentMetadata, oneOrTwofoldEncryptedKey, documentData) = self.documentStore.encryptedDocument(with: documentIdentifier) {
            switch oneOrTwofoldEncryptedKey.content {
            case let .onefoldEncryptedKey(onefoldEncryptedKey):
                retrieveDocumentSubject.send(try! self.documentUrl(for: documentData, with: documentMetadata, key: onefoldEncryptedKey))
                retrieveDocumentSubject.send(completion: .finished)
                break
            case .twofoldEncryptedKey:
                server.missingEncryptedDocumentKeysForTerminalSubject.send(documentIdentifier)
                self.retrieveDocumentSubject = retrieveDocumentSubject
                retrieveDocumentIdentifier = documentIdentifier
                retrieveDocumentData = documentData
                retrieveDocumentMetadata = documentMetadata
                break
            default:
                break
            }
        } else {
            server.missingDocumentsForTerminalSubject.send(documentIdentifier)
            server.missingEncryptedDocumentKeysForTerminalSubject.send(documentIdentifier)
            self.retrieveDocumentSubject = retrieveDocumentSubject
            retrieveDocumentIdentifier = documentIdentifier
        }
        return retrieveDocumentSubject.eraseToAnyPublisher()
    }
    
    private func documentUrl(for encryptedData: Data, with metadata: HealthEnclave_DocumentMetadata, key: HealthEnclave_EncryptedDocumentKey) throws -> URL {
        guard let sharedKey = sharedKey else {
            throw ApplicationError.missingSharedKey
        }
        
        let document = try TerminalCryptography.decryptDocument(encryptedData, with: key, using: sharedKey, authenticating: metadata)
        let url = cacheDirectory.appendingPathComponent(metadata.id.uuid)
        try document.write(to: url)
        return url
    }
    
    private func setupDeviceAdvertisedDocumentsSubscription() {
        deviceAdvertisedDocumentsSubscription = server.deviceAdvertisedDocumentsSubject
            .receive(on: DispatchQueue.global())
            .sink() { [weak self] documentMetadata in
                guard let self = self else { return }
                self._documentsMetadata.insert(documentMetadata)
                self._documentAddedSubject.send(documentMetadata)
                // TODO start transfering missing document from device to terminal
        }
    }
    
    private func setupTransferDocumentToDeviceRequestSubscription() {
        // Transfer document to device.
        transferDocumentToDeviceRequestSubscription = server.transferDocumentToDeviceRequestSubject
            .receive(on: DispatchQueue.global())
            .sink() { [weak self] (identifier, documentStreamSubject) in
                guard let self = self else { return }
                try! self.documentStore.requestDocumentStream(for: identifier, on: documentStreamSubject)
        }
    }
    
    private func setupDocumentSubscription() {
        // Store twofold encrypted key when received.
        documentSubscription = server.documentSubject
            .receive(on: DispatchQueue.global())
            .sink { [weak self] documentStream in
                guard let self = self else { return }
                
                var metadata: HealthEnclave_DocumentMetadata?
                var key: HealthEnclave_TwofoldEncryptedDocumentKey?
                var data = Data()
                
                var documentStreamSubscription: AnyCancellable?
                documentStreamSubscription = documentStream.sink(receiveCompletion: { completion in
                    if case .finished = completion,
                        let metadata = metadata,
                        let key = key {
                        if self.retrieveDocumentSubject != nil {
                            self.retrieveDocumentMetadata = metadata
                            self.retrieveDocumentData = data
                            
                            self.resolveRetrieveDocument()
                        }
                        
                        
                        try! self.documentStore.addTwofoldEncryptedDocument(data, with: metadata, encryptedWith: key)
                    }
                    self.documentStreamSubscriptions.remove(documentStreamSubscription!)
                }, receiveValue: { chunk in
                    switch chunk.content {
                    case let .metadata(m):
                        metadata = m
                    case let .key(k):
                        key = k
                    case let .chunk(d):
                        data.append(d)
                    default:
                        break
                    }
                })
                
                self.documentStreamSubscriptions.insert(documentStreamSubscription!)
        }
    }
    
    private func setupEncryptedDocumentKeySubscription() {
        // Store twofold encrypted key when received.
        encryptedDocumentKeySubscription = server.encryptedDocumentKeySubject
            .receive(on: DispatchQueue.global())
            .sink { [weak self] encryptedDocumentKeyWithId in
                guard let self = self else { return }
                if self.retrieveDocumentSubject != nil {
                    self.retrieveDocumentKey = encryptedDocumentKeyWithId.key
                }
                self.resolveRetrieveDocument()
                try! self.documentStore.addEncryptedDocumentKey(encryptedDocumentKeyWithId.key,
                                                                for: encryptedDocumentKeyWithId.id)
        }
    }
    
    private func resolveRetrieveDocument() {
        if let retrieveDocumentSubject = self.retrieveDocumentSubject,
            let documentMetadata = self.retrieveDocumentMetadata,
            let documentData = self.retrieveDocumentData,
            let documentKey = self.retrieveDocumentKey {
            self.retrieveDocumentSubject = nil
            retrieveDocumentSubject.send(try! self.documentUrl(for: documentData, with: documentMetadata, key: documentKey))
            retrieveDocumentSubject.send(completion: .finished)
        }
    }
    
    private func setupTwofoldEncryptedDocumentKeySubscription() {
        // Store twofold encrypted key when received.
        twofoldEncryptedDocumentKeySubscription = server.twofoldEncryptedDocumentKeySubject
            .receive(on: DispatchQueue.global())
            .sink { [weak self] twofoldEncryptedDocumentKeyWithId in
                guard let self = self else { return }
                try! self.documentStore.addTwofoldEncryptedDocumentKey(twofoldEncryptedDocumentKeyWithId.key,
                                                                       for: twofoldEncryptedDocumentKeyWithId.id)
        }
    }
}
