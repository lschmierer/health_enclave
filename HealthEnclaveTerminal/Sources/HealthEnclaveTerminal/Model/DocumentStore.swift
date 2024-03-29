//
//  DocumentStore.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 23.06.20.
//
import Foundation
import Logging

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

import HealthEnclaveCommon

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.DocumentStore")

private let chunkSize = 16 * 1024

private let globalStorageFolder = applicationSupportDirectory.appendingPathComponent("Storage", isDirectory: true)
private let globalDocumentsFolder = globalStorageFolder.appendingPathComponent("Documents", isDirectory: true)
private let globalMetadataFolder = globalStorageFolder.appendingPathComponent("Metadata", isDirectory: true)
private let globalDocumentKeysFolder = globalStorageFolder.appendingPathComponent("Document Keys", isDirectory: true)

enum DocumentStoreError: Error {
    case missingMetadata
    case missingKey
}

class DocumentStore {
    private let deviceIdentifier: DeviceCryptography.DeviceIdentifier
    
    private let documentsFolder: URL
    private let metadataFolder: URL
    private let documentKeysFolder: URL
    
    private var documentsMetadata =
        [HealthEnclave_DocumentIdentifier: HealthEnclave_DocumentMetadata]()
    private var encryptedDocumentKeys =
        [HealthEnclave_DocumentIdentifier: HealthEnclave_EncryptedDocumentKey]()
    
    init(for deviceIdentifier: DeviceCryptography.DeviceIdentifier) throws {
        self.deviceIdentifier = deviceIdentifier
        
        // 255 is the max allowed filename length
        let deviceIdentfierFolder = deviceIdentifier.hexEncodedString
        
        metadataFolder = globalMetadataFolder.appendingPathComponent(deviceIdentfierFolder, isDirectory: true)
        documentsFolder = globalDocumentsFolder.appendingPathComponent(deviceIdentfierFolder, isDirectory: true)
        documentKeysFolder = globalDocumentKeysFolder.appendingPathComponent(deviceIdentfierFolder, isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: metadataFolder.path) {
            try FileManager.default.createDirectory(at: metadataFolder, withIntermediateDirectories: true, attributes: nil)
        }
        if !FileManager.default.fileExists(atPath: documentsFolder.path) {
            try FileManager.default.createDirectory(at: documentsFolder, withIntermediateDirectories: true, attributes: nil)
        }
        if !FileManager.default.fileExists(atPath: documentKeysFolder.path) {
            try FileManager.default.createDirectory(at: documentKeysFolder, withIntermediateDirectories: true, attributes: nil)
        }
        
        try readMetadata()
    }
    
    func storeEncryptedDocument(_ document: Data,
                                with metadata: HealthEnclave_DocumentMetadata,
                                encryptedWith encryptedKey: HealthEnclave_EncryptedDocumentKey) throws {
        documentsMetadata[metadata.id] = metadata
        encryptedDocumentKeys[metadata.id] = encryptedKey
        try storeDocument(document, with: metadata.id)
        try storeMetadata(metadata, with: metadata.id)
    }
    
    func storeTwofoldEncryptedDocument(_ document: Data,
                                       with metadata: HealthEnclave_DocumentMetadata,
                                       encryptedWith encryptedKey: HealthEnclave_TwofoldEncryptedDocumentKey) throws {
        documentsMetadata[metadata.id] = metadata
        try storeDocument(document, with: metadata.id)
        try storeMetadata(metadata, with: metadata.id)
        try storeTwofoldEncryptedKey(encryptedKey, with: metadata.id)
    }
    
    func storeEncryptedDocumentKey(_ key: HealthEnclave_EncryptedDocumentKey,
                                   for identifier: HealthEnclave_DocumentIdentifier) throws {
        encryptedDocumentKeys[identifier] = key
    }
    
    func storeTwofoldEncryptedDocumentKey(_ key: HealthEnclave_TwofoldEncryptedDocumentKey,
                                          for identifier: HealthEnclave_DocumentIdentifier) throws {
        try storeTwofoldEncryptedKey(key, with: identifier)
    }
    
    func delete(with identifier: HealthEnclave_DocumentIdentifier) throws {
        documentsMetadata[identifier] = nil
        try deleteDocument(with: identifier)
        try deleteMetadata(with: identifier)
        try deleteTwofoldEncryptedKey(with: identifier)
    }
    
    func allDocumentsMetadata() -> [HealthEnclave_DocumentMetadata] {
        return Array(documentsMetadata.values)
    }
    
    func metadata(for identifier: HealthEnclave_DocumentIdentifier) -> HealthEnclave_DocumentMetadata? {
        return documentsMetadata[identifier]
    }
    
    func encryptedDocumentKey(with identifier: HealthEnclave_DocumentIdentifier) -> HealthEnclave_EncryptedDocumentKey? {
        return encryptedDocumentKeys[identifier]
    }
    
    func twofoldEncryptedDocumentKey(with identifier: HealthEnclave_DocumentIdentifier) throws -> HealthEnclave_TwofoldEncryptedDocumentKey? {
        return try readTwofoldEncryptedDocumentKey(for: identifier)
    }
    
    func encryptedDocument(with identifier: HealthEnclave_DocumentIdentifier) throws -> Data? {
        return try readDocument(for: identifier)
    }
    
    func encryptedDocumentStream(for identifier: HealthEnclave_DocumentIdentifier,
                                 on documentStreamSubject: PassthroughSubject<HealthEnclave_OneOrTwofoldEncyptedDocumentChunked, Never>) throws {
        guard let metadata = documentsMetadata[identifier] else {
            throw DocumentStoreError.missingMetadata
        }
        
        var key: HealthEnclave_OneOrTwofoldEncyptedDocumentKey?
        if let twofoldEncryptedKey = try readTwofoldEncryptedDocumentKey(for: identifier) {
            key = HealthEnclave_OneOrTwofoldEncyptedDocumentKey.with {
                $0.twofoldEncryptedKey = twofoldEncryptedKey
            }
        } else if let onefoldEncryptedKey = encryptedDocumentKeys[identifier] {
            key = HealthEnclave_OneOrTwofoldEncyptedDocumentKey.with {
                $0.onefoldEncryptedKey = onefoldEncryptedKey
            }
        } else {
            throw DocumentStoreError.missingKey
        }
        
        let data = try readDocument(for: identifier)
        
        documentStreamSubject.send(HealthEnclave_OneOrTwofoldEncyptedDocumentChunked.with {
            $0.metadata = metadata
        })
        
        documentStreamSubject.send(HealthEnclave_OneOrTwofoldEncyptedDocumentChunked.with {
            $0.key = key!
        })
        
        let fullChunks = Int(data.count / chunkSize)
        let totalChunks = fullChunks + (data.count % chunkSize != 0 ? 1 : 0)
        
        for chunkCounter in 0..<totalChunks
        {
            var chunk: Data
            let chunkBase = chunkCounter * chunkSize
            var diff = chunkSize
            if chunkCounter == totalChunks - 1
            {
                diff = data.count - chunkBase
            }
            chunk = data.subdata(in: chunkBase..<(chunkBase + diff))
            
            documentStreamSubject.send(HealthEnclave_OneOrTwofoldEncyptedDocumentChunked.with {
                $0.chunk = chunk
            })
        }
        documentStreamSubject.send(completion: .finished)
    }
    
    private func readMetadata() throws {
        try FileManager.default.contentsOfDirectory(at: metadataFolder, includingPropertiesForKeys: []).forEach { url in
            if let uuid = UUID(uuidString: url.lastPathComponent) {
                do {
                    let documentIdentifier = HealthEnclave_DocumentIdentifier.with {
                        $0.uuid = uuid.uuidString
                    }
                    
                    let documentMetadata = try HealthEnclave_DocumentMetadata(serializedData: Data(contentsOf: url))
                    
                    documentsMetadata[documentIdentifier] = documentMetadata
                } catch {
                    logger.error("Error reading \(url)")
                }
            }
        }
    }
    
    private func readTwofoldEncryptedDocumentKey(for identifier: HealthEnclave_DocumentIdentifier) throws
        -> HealthEnclave_TwofoldEncryptedDocumentKey? {
            let keyFile = documentKeysFolder.appendingPathComponent(identifier.uuid)
            if FileManager.default.fileExists(atPath: keyFile.path) {
                return try HealthEnclave_TwofoldEncryptedDocumentKey(serializedData: Data(contentsOf: keyFile))
            } else {
                return nil
            }
    }
    
    private func readDocument(for identifier: HealthEnclave_DocumentIdentifier) throws
        -> Data {
            let keyFile = documentsFolder.appendingPathComponent(identifier.uuid)
            return try Data(contentsOf: keyFile)
    }
    
    private func storeMetadata(_ metadata: HealthEnclave_DocumentMetadata,
                               with identifier: HealthEnclave_DocumentIdentifier) throws {
        let uri = metadataFolder.appendingPathComponent(identifier.uuid)
        try metadata.serializedData().write(to: uri)
    }
    
    private func storeTwofoldEncryptedKey(_ key: HealthEnclave_TwofoldEncryptedDocumentKey,
                                          with identifier: HealthEnclave_DocumentIdentifier) throws {
        let uri = documentKeysFolder.appendingPathComponent(identifier.uuid)
        try key.serializedData().write(to: uri)
    }
    
    private func storeDocument(_ document: Data,
                               with identifier: HealthEnclave_DocumentIdentifier) throws {
        let uri = documentsFolder.appendingPathComponent(identifier.uuid)
        try document.write(to: uri)
    }
    private func deleteDocument(with identifier: HealthEnclave_DocumentIdentifier) throws {
        let uri = documentsFolder.appendingPathComponent(identifier.uuid)
        if FileManager.default.fileExists(atPath: uri.path) {
            try FileManager.default.removeItem(at: uri)
        }
    }
    
    private func deleteMetadata(with identifier: HealthEnclave_DocumentIdentifier) throws {
        let uri = metadataFolder.appendingPathComponent(identifier.uuid)
        if FileManager.default.fileExists(atPath: uri.path) {
            try FileManager.default.removeItem(at: uri)
        }
    }
    
    private func deleteTwofoldEncryptedKey(with identifier: HealthEnclave_DocumentIdentifier) throws {
        let uri = documentKeysFolder.appendingPathComponent(identifier.uuid)
        if FileManager.default.fileExists(atPath: uri.path) {
            try FileManager.default.removeItem(at: uri)
        }
    }
}
