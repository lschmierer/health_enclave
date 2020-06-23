//
//  DocumentStore.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 23.06.20.
//
import Foundation
import HealthEnclaveCommon

class DocumentStore {
    private let deviceIdentifier: HealthEnclave_DeviceIdentifier
    
    private var documentsMetadata =
        [HealthEnclave_DocumentIdentifier: HealthEnclave_DocumentMetadata]()
    private var encryptedDocuments =
        [HealthEnclave_DocumentIdentifier: Data]()
    private var encryptedDocumentKeys =
        [HealthEnclave_DocumentIdentifier: HealthEnclave_EncryptedDocumentKey]()
    private var twofoldEncryptedDocumentKeys =
        [HealthEnclave_DocumentIdentifier: HealthEnclave_TwofoldEncryptedDocumentKey]()
    
    init(for deviceIdentifier: HealthEnclave_DeviceIdentifier) {
        self.deviceIdentifier = deviceIdentifier
        
        // TODO: load from hard drive
    }
    
    func addNewEncryptedDocument(_ document: Data,
                                 with metadata: HealthEnclave_DocumentMetadata,
                                 encryptedWith encryptedKey: HealthEnclave_EncryptedDocumentKey) {
        // TODO: store on hard drive
        
        debugPrint(document)
        debugPrint(metadata)
        debugPrint(encryptedKey)
        
        encryptedDocuments[metadata.id] = document
        documentsMetadata[metadata.id] = metadata
        encryptedDocumentKeys[metadata.id] = encryptedKey
    }
    
    func addTwofoldEncryptedDocumentKey(_ key: HealthEnclave_TwofoldEncryptedDocumentKey, for identifier: HealthEnclave_DocumentIdentifier) {
        // TODO: store on hard drive
        
        twofoldEncryptedDocumentKeys[identifier] = key
    }
}
