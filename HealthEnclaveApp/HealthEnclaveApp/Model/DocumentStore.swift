//
//  DocumentStore.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 03.07.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import os
import Foundation
import Combine

import HealthEnclaveCommon

private let chunkSize = 16 * 1024

private let applicationSupportDirectory = try! FileManager.default.url(for: .applicationSupportDirectory,
                                                                       in: .userDomainMask,
                                                                       appropriateFor: nil, create: true)

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
    
    private var documentStreamSubscriptions = Set<AnyCancellable>()
    
    init(for deviceIdentifier: DeviceCryptography.DeviceIdentifier) throws {
        self.deviceIdentifier = deviceIdentifier
        
        // 255 is the max allowed filename length
        let deviceIdentfierFolder = String(deviceIdentifier.hexEncodedString.prefix(255))
        
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
    
    func store(from documentStreamSubject: AnyPublisher<HealthEnclave_TwofoldEncyptedDocumentChunked, Error>) {
        var metadata: HealthEnclave_DocumentMetadata?
        var key: HealthEnclave_TwofoldEncryptedDocumentKey?
        var data = Data()
        
        var documentStreamSubscription: AnyCancellable?
        documentStreamSubscription = documentStreamSubject
            .receive(on: DispatchQueue.global())
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                self.documentStreamSubscriptions.remove(documentStreamSubscription!)
                
                switch completion {
                case .finished:
                    guard let metadata = metadata else {
                        os_log(.error, "Storing document failed: metadata missing")
                        return
                    }
                    guard let key = key else {
                        os_log(.error, "Storing document failed: key missing")
                        return
                    }
                    guard !data.isEmpty else {
                        os_log(.error, "Storing document failed: data missing")
                        return
                    }
                    
                    os_log(.info, "Stored Document with id: %@", metadata.id.uuid)
                    
                    self.documentsMetadata[metadata.id] = metadata
                    try! self.storeMetadata(metadata, with: metadata.id)
                    try! self.storeTwofoldEncryptedKey(key, with: metadata.id)
                    try! self.storeDocument(data, with: metadata.id)
                    break
                case let .failure(error):
                    os_log(.error, "Storing document failed: %@", error.localizedDescription)
                }
            }, receiveValue: { chunk in
                switch chunk.content {
                case let .metadata(m):
                    metadata = m
                case let .key(k):
                    key = k
                case let .chunk(c):
                    data.append(c)
                default: break
                }
            })
        documentStreamSubscriptions.insert(documentStreamSubscription!)
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
    
    func twofoldEncryptedDocumentKey(with identifier: HealthEnclave_DocumentIdentifier) throws -> HealthEnclave_TwofoldEncryptedDocumentKey? {
        return try readTwofoldEncryptedDocumentKey(for: identifier)
    }
    
    func encryptedDocumentChunked(for identifier: HealthEnclave_DocumentIdentifier) throws -> [HealthEnclave_TwofoldEncyptedDocumentChunked] {
        guard let metadata = documentsMetadata[identifier] else {
            throw DocumentStoreError.missingMetadata
        }
        
        guard let key = try readTwofoldEncryptedDocumentKey(for: identifier)  else {
            throw DocumentStoreError.missingKey
        }
        
        var chunks = [HealthEnclave_TwofoldEncyptedDocumentChunked]()
        
        let data = try readDocument(for: identifier)
        
        chunks.append(HealthEnclave_TwofoldEncyptedDocumentChunked.with {
            $0.metadata = metadata
        })
        
        chunks.append(HealthEnclave_TwofoldEncyptedDocumentChunked.with {
            $0.key = key
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
            
            chunks.append(HealthEnclave_TwofoldEncyptedDocumentChunked.with {
                $0.chunk = chunk
            })
        }
        return chunks
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
                    os_log(.error, "Error reading: %@", String(reflecting: url))
                }
            }
        }
    }
    
    private func readDocument(for identifier: HealthEnclave_DocumentIdentifier) throws
    -> Data {
        let keyFile = documentsFolder.appendingPathComponent(identifier.uuid)
        return try Data(contentsOf: keyFile)
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
    
    private func storeDocument(_ document: Data,
                               with identifier: HealthEnclave_DocumentIdentifier) throws {
        let uri = documentsFolder.appendingPathComponent(identifier.uuid)
        try document.write(to: uri)
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
