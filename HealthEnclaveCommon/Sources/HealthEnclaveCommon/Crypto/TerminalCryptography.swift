//
//  TerminalCryptography.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 22.06.20.
//
import Foundation

public enum TerminalCryptography {
    public class SharedKey: CryptoPrimitives.SymmetricKey {}
    
    public static func encryptDocument(_ document: Data,
                                       using sharedKey: SharedKey,
                                       authenticating metadata: HealthEnclave_DocumentMetadata) throws
        -> (HealthEnclave_EncryptedDocumentKey, Data) {
            let metadata = try metadata.serializedData()
            let documentKey = CryptoPrimitives.SymmetricKey()
            let encryptedDocument = try CryptoPrimitives.encryptSymmetric(document,
                                                                          using: documentKey,
                                                                          authenticating: metadata)
            let encryptedDocumentKey = try HealthEnclave_EncryptedDocumentKey.with {
                $0.data = try CryptoPrimitives.encryptSymmetric(documentKey.data,
                                                                using: sharedKey,
                                                                authenticating: metadata)
            }
            return (encryptedDocumentKey, encryptedDocument)
    }
    
    public static func decryptDocument(_ encryptedDocument: Data,
                                       with documentKey: HealthEnclave_EncryptedDocumentKey,
                                       using sharedKey: SharedKey,
                                       authenticating metadata: HealthEnclave_DocumentMetadata) throws
        -> Data {
            let metadata = try metadata.serializedData()
            let documentKey = try CryptoPrimitives.SymmetricKey(data: try CryptoPrimitives.decryptSymmetric(documentKey.data,
                                                                                                             using: sharedKey,
                                                                                                             authenticating: metadata))
            return try CryptoPrimitives.decryptSymmetric(encryptedDocument, using: documentKey, authenticating: metadata)
    }
}
