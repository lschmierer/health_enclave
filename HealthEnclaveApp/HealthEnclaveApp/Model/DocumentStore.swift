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

private let applicationSupportDirectory = try! FileManager.default.url(for: .applicationSupportDirectory,
                                                                       in: .userDomainMask,
                                                                       appropriateFor: nil, create: true)

private let globalStorageFolder = applicationSupportDirectory.appendingPathComponent("Storage", isDirectory: true)
private let globalDocumentsFolder = globalStorageFolder.appendingPathComponent("Documents", isDirectory: true)
private let globalMetadataFolder = globalStorageFolder.appendingPathComponent("Metadata", isDirectory: true)
private let globalDocumentKeysFolder = globalStorageFolder.appendingPathComponent("Document Keys", isDirectory: true)

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
    
    func allDocumentsMetadata() -> [HealthEnclave_DocumentMetadata] {
        return Array(documentsMetadata.values)
    }
    
    func storeDocument(from documentStreamSubject: AnyPublisher<HealthEnclave_TwofoldEncyptedDocumentChunked, Error>) {
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
                        os_log(.error, "Receiving document failed: metadata missing")
                        return
                    }
                    guard let key = key else {
                        os_log(.error, "Receiving document failed: key missing")
                        return
                    }
                    guard !data.isEmpty else {
                        os_log(.error, "Receiving document failed: data missing")
                        return
                    }
                    
                    os_log(.info, "Received DOcument with id: %@", metadata.id.uuid)
                    
                    self.documentsMetadata[metadata.id] = metadata
                    try! self.storeMetadata(metadata, with: metadata.id)
                    try! self.storeTwofoldEncryptedKey(key, with: metadata.id)
                    try! self.storeDocument(data, with: metadata.id)
                    break
                case let .failure(error):
                    os_log(.error, "Receiving document failed: %@", error.localizedDescription)
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
}
