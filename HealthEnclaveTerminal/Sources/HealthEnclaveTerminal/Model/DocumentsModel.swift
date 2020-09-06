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

// Give the device some time to advertise documents before
// sending a list of missing documents for device.
private let advertiseTimeout = DispatchTimeInterval.seconds(1)

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
    
    private var retrieveDocumentSubject: PassthroughSubject<URL, ApplicationError>?
    private var retrieveDocumentIdentifier: HealthEnclave_DocumentIdentifier?
    private var retrieveDocumentMetadata: HealthEnclave_DocumentMetadata?
    private var retrieveDocumentKey: HealthEnclave_EncryptedDocumentKey?
    private var retrieveDocumentData: Data?
    
    private var deviceAdvertisedDocumentsSubscription: Cancellable?
    private var deleteDocumentsSubscription: Cancellable?
    private var transferDocumentToDeviceSubscription: Cancellable?
    private var transferDocumentToTerminalSubscription: Cancellable?
    private var documentStreamSubscriptions = Set<AnyCancellable>()
    private var encryptedDocumentKeySubscription: Cancellable?
    private var encryptedDocumentKeyNotSubscription: Cancellable?
    private var twofoldEncryptedDocumentKeySubscription: Cancellable?
    
    init(documentStore: DocumentStore, server: HealthEnclaveServer) {
        self.documentStore = documentStore
        self.server = server
        
        setupDeviceAdvertisedDocumentsSubscription()
        setupDeleteDocumentsSubscription()
        setupTransferDocumentToDeviceSubscription()
        setupTransferDocumentToTerminalSubscription()
        setupEncryptedDocumentKeySubscription()
        setupEncryptedDocumentKeyNotSubscription()
        setupTwofoldEncryptedDocumentKeySubscription()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + advertiseTimeout) { [weak self] in
            guard let self = self else { return }
            
            let documentsMetadata = documentStore.allDocumentsMetadata()
            for metadata in documentsMetadata {
                if !self._documentsMetadata.contains(metadata) {
                    server.missingDocumentsForDeviceSubject.send(metadata.id)
                }
            }
        }
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
        
        try documentStore.storeEncryptedDocument(encryptedDocument, with: documentMetadata, encryptedWith: encryptedDocumentKey)
        
        server.missingDocumentsForDeviceSubject.send(documentIdentifier)
        _documentAddedSubject.send(documentMetadata)
    }
    
    func retrieveDocument(_ documentIdentifier: HealthEnclave_DocumentIdentifier) throws -> AnyPublisher<URL, ApplicationError> {
        if let retrieveDocumentSubject = retrieveDocumentSubject {
            retrieveDocumentSubject.send(completion: .finished)
        }
        
        let retrieveDocumentSubject = PassthroughSubject<URL, ApplicationError>()
        self.retrieveDocumentSubject = retrieveDocumentSubject
        retrieveDocumentIdentifier = documentIdentifier
        
        if let documentMetadata = self.documentStore.metadata(for: documentIdentifier),
            let documentData = try! self.documentStore.encryptedDocument(with: documentIdentifier) {
            
            retrieveDocumentMetadata = documentMetadata
            retrieveDocumentData = documentData
            
            if let encryptedDocumentKey = self.documentStore.encryptedDocumentKey(with: documentIdentifier) {
                retrieveDocumentKey = encryptedDocumentKey
                DispatchQueue.global().async { [weak self] in
                    self?.resolveRetrieveDocument()
                }
            } else if try! self.documentStore.twofoldEncryptedDocumentKey(with: documentIdentifier) != nil {
                retrieveDocumentKey = nil
                server.missingEncryptedDocumentKeysForTerminalSubject.send(documentIdentifier)
            }
        } else {
            retrieveDocumentMetadata = nil
            retrieveDocumentData = nil
            // We might already have sent a missing document request (in setupDeviceAdvertisedDocumentsSubscription).
            // Sending it again, however, tells the device to prioritize this document.
            server.missingDocumentsForTerminalSubject.send(documentIdentifier)
            server.missingEncryptedDocumentKeysForTerminalSubject.send(documentIdentifier)
        }
        
        return retrieveDocumentSubject.eraseToAnyPublisher()
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
    
    private func documentUrl(for encryptedData: Data, with metadata: HealthEnclave_DocumentMetadata, key: HealthEnclave_EncryptedDocumentKey) throws -> URL {
        guard let sharedKey = sharedKey else {
            throw ApplicationError.missingSharedKey
        }
        
        let document = try TerminalCryptography.decryptDocument(encryptedData, with: key, using: sharedKey, authenticating: metadata)
        let tempFolder = cacheDirectory.appendingPathComponent(metadata.id.uuid, isDirectory: true)
        if !FileManager.default.fileExists(atPath: tempFolder.path) {
            try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: false, attributes: nil)
        }
        let url = tempFolder.appendingPathComponent(metadata.name)
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
                
                if self.documentStore.metadata(for: documentMetadata.id) == nil {
                    self.server.missingDocumentsForTerminalSubject.send(documentMetadata.id)
                }
        }
    }
    
    private func setupDeleteDocumentsSubscription() {
        deleteDocumentsSubscription = server.deleteDocumentsSubject
            .receive(on: DispatchQueue.global())
            .sink() { [weak self] documentIdentifier in
                guard let self = self else { return }
                try? self.documentStore.delete(with: documentIdentifier)
        }
    }
    
    private func setupTransferDocumentToDeviceSubscription() {
        // Transfer document to device.
        transferDocumentToDeviceSubscription = server.transferDocumentToDeviceRequestSubject
            .receive(on: DispatchQueue.global())
            .sink() { [weak self] (identifier, documentStreamSubject) in
                guard let self = self else { return }
                try! self.documentStore.encryptedDocumentStream(for: identifier,
                                                                on: documentStreamSubject)
        }
    }
    
    private func setupTransferDocumentToTerminalSubscription() {
        transferDocumentToTerminalSubscription = server.documentSubject
            .receive(on: DispatchQueue.global())
            .sink { [weak self] documentStream in
                guard let self = self else { return }
                
                var metadata: HealthEnclave_DocumentMetadata?
                var key: HealthEnclave_TwofoldEncryptedDocumentKey?
                var data = Data()
                
                var documentStreamSubscription: AnyCancellable?
                documentStreamSubscription = documentStream
                    .buffer(size: .max, prefetch: .keepFull, whenFull: .dropNewest)
                    .sink(receiveCompletion: { completion in
                        if case .finished = completion,
                            let metadata = metadata,
                            let key = key {
                            try! self.documentStore.storeTwofoldEncryptedDocument(data, with: metadata, encryptedWith: key)
                            
                            if self.retrieveDocumentSubject != nil,
                                self.retrieveDocumentIdentifier == metadata.id {
                                self.retrieveDocumentMetadata = metadata
                                self.retrieveDocumentData = data
                                
                                self.resolveRetrieveDocument()
                            }
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
                try! self.documentStore.storeEncryptedDocumentKey(encryptedDocumentKeyWithId.key,
                                                                  for: encryptedDocumentKeyWithId.id)
                
                if self.retrieveDocumentSubject != nil,
                    self.retrieveDocumentIdentifier == encryptedDocumentKeyWithId.id {
                    self.retrieveDocumentKey = encryptedDocumentKeyWithId.key
                    self.resolveRetrieveDocument()
                }
        }
    }
    
    private func setupEncryptedDocumentKeyNotSubscription() {
        // Store twofold encrypted key when received.
        encryptedDocumentKeyNotSubscription = server.encryptedDocumentKeyNotSubject
            .receive(on: DispatchQueue.global())
            .sink { [weak self] documentIdentifier in
                guard let self = self else { return }
                if let retrieveDocumentSubject = self.retrieveDocumentSubject,
                    self.retrieveDocumentIdentifier == documentIdentifier {
                    self.retrieveDocumentSubject = nil
                    retrieveDocumentSubject.send(completion: .failure(.noDocumentPermission))
                }
        }
    }
    
    private func setupTwofoldEncryptedDocumentKeySubscription() {
        // Store twofold encrypted key when received.
        twofoldEncryptedDocumentKeySubscription = server.twofoldEncryptedDocumentKeySubject
            .receive(on: DispatchQueue.global())
            .sink { [weak self] twofoldEncryptedDocumentKeyWithId in
                guard let self = self else { return }
                try! self.documentStore.storeTwofoldEncryptedDocumentKey(twofoldEncryptedDocumentKeyWithId.key,
                                                                         for: twofoldEncryptedDocumentKeyWithId.id)
        }
    }
}
