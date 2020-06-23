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
    private let sharedKey: TerminalCryptography.SharedKey
    private let documentStore: DocumentStore
    private let server: HealthEnclaveServer
    
    private var twofoldEncryptedDocumentKeySubscription: Cancellable?
    
    init(sharedKey: TerminalCryptography.SharedKey, documentStore: DocumentStore, server: HealthEnclaveServer) {
        self.sharedKey = sharedKey
        self.documentStore = documentStore
        self.server = server
        
        // Store twofold encrypted key when received
        twofoldEncryptedDocumentKeySubscription = server.twofoldEncryptedDocumentKeySubject
            .sink { twofoldEncryptedDocumentKeyWithId in
                documentStore.addTwofoldEncryptedDocumentKey(twofoldEncryptedDocumentKeyWithId.key,
                                                             for: twofoldEncryptedDocumentKeyWithId.id)
        }
    }
    
    func addDocumentToDevice(file: URL) throws {
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
        
        documentStore.addNewEncryptedDocument(encryptedDocument, with: documentMetadata, encryptedWith: encryptedDocumentKey)
        
        server.missingDocumentsForDeviceSubject.send(documentIdentifier)
    }
}
