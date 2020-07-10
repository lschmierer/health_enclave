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
    
    private var deviceAdvertisedDocumentsSubscription: Cancellable?
    private var twofoldEncryptedDocumentKeySubscription: Cancellable?
    private var transferDocumentToDeviceRequestSubscription: Cancellable?
    
    init(documentStore: DocumentStore, server: HealthEnclaveServer) {
        self.documentStore = documentStore
        self.server = server
        
        setupDeviceAdvertisedDocumentsSubscription()
        setupTwofoldEncryptedDocumentKeySubscription()
        setupTransferDocumentToDeviceRequestSubscription()
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
    
    private func setupDeviceAdvertisedDocumentsSubscription() {
        deviceAdvertisedDocumentsSubscription = server.deviceAdvertisedDocumentsSubject
            .receive(on: DispatchQueue.global())
            .sink() { [weak self] documentMetadata in
                guard let self = self else { return }
                self._documentsMetadata.insert(documentMetadata)
                self._documentAddedSubject.send(documentMetadata)
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
    
    private func setupTransferDocumentToDeviceRequestSubscription() {
        // Transfer document to device.
        transferDocumentToDeviceRequestSubscription = server.transferDocumentToDeviceRequestSubject
            .receive(on: DispatchQueue.global())
            .sink() { [weak self] (identifier, documentStreamSubject) in
            guard let self = self else { return }
                try! self.documentStore.requestDocumentStream(for: identifier, on: documentStreamSubject)
        }
    }
}
