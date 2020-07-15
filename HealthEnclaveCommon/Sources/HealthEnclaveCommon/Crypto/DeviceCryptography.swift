//
//  DeviceCryptography.swift
//  
//
//  Created by Lukas Schmierer on 23.06.20.
//

import Foundation

extension Data {
    init?(hexEncoded: String) {
        let length = hexEncoded.count / 2
        var data = Data(capacity: length)
        for i in 0 ..< length {
            let j = hexEncoded.index(hexEncoded.startIndex, offsetBy: i * 2)
            let k = hexEncoded.index(j, offsetBy: 2)
            let bytes = hexEncoded[j..<k]
            if var byte = UInt8(bytes, radix: 16) {
                data.append(&byte, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
    
    func hexEncodedString() -> String {
        let hexDigits = Array("0123456789abcdef".utf16)
        var chars: [unichar] = []
        chars.reserveCapacity(2 * count)
        for byte in self {
            chars.append(hexDigits[Int(byte / 16)])
            chars.append(hexDigits[Int(byte % 16)])
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}

public enum DeviceCryptography {
    public struct DeviceIdentifier: Equatable {
        let data: Data
        
        public init() {
            data = Data(CryptoPrimitives.randomBytes(count: 256))
        }
        
        public init?(hexEncoded hex: String) {
            if let data = Data(hexEncoded: hex),
                data.count == 256 {
                self.data = data
            } else {
                return nil
            }
        }
        
        public var hexEncodedString: String {
            get {
                return data.hexEncodedString()
            }
        }
    }
    
    public class DeviceKey: CryptoPrimitives.SymmetricKey {}
    
    public static func encryptEncryptedDocumentKey(_ documentKey: HealthEnclave_EncryptedDocumentKey,
                                                   using deviceKey: DeviceKey,
                                                   authenticating metadata: HealthEnclave_DocumentMetadata) throws
        -> HealthEnclave_TwofoldEncryptedDocumentKey {
            let documentKey = try documentKey.serializedData()
            let metadata = try metadata.serializedData()
            return try HealthEnclave_TwofoldEncryptedDocumentKey.with {
                $0.data = try CryptoPrimitives.encryptSymmetric(documentKey,
                                                                using: deviceKey,
                                                                authenticating: metadata)
            }
    }
    
    public static func decryptTwofoldEncryptedDocumentKey(_ documentKey: HealthEnclave_TwofoldEncryptedDocumentKey,
                                                          using deviceKey: DeviceKey,
                                                          authenticating metadata: HealthEnclave_DocumentMetadata) throws
        -> HealthEnclave_EncryptedDocumentKey {
            let metadata = try metadata.serializedData()
            return try HealthEnclave_EncryptedDocumentKey(serializedData: try CryptoPrimitives.decryptSymmetric(documentKey.data,
                                                                                                                using: deviceKey,
                                                                                                                authenticating: metadata))
    }
}
