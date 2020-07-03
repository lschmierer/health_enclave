//
//  CryptoPrimitives.swift
//  
//
//  Created by Lukas Schmierer on 17.03.20.
//
import Foundation
import Crypto

public enum CryptoError: Error {
    case invalidSize
}

public enum CryptoPrimitives {
    public struct SymmetricKey {
        let key: Crypto.SymmetricKey
        
        var data: Data {
            get {
                return key.withUnsafeBytes { Data($0) }
            }
        }
        
        init() {
            key = Crypto.SymmetricKey(size: .bits256)
        }
        
        init(data: Data) throws {
            key = Crypto.SymmetricKey(data: data)
            if key.bitCount != 256 {
                throw CryptoError.invalidSize
            }
        }
    }
    
    public static func randomBytes(count: Int) -> [UInt8] {
        // SystemRandomNumberGenerator is cryptographically secure.
        // Uses arc4random_buf(3) on Apple platforms,
        //      getrandom(2) on Linux platforms when available; otherwise, /dev/urandom and
        //      BCryptGenRandom on Windows.
        var g = SystemRandomNumberGenerator()
        return (0..<count).map( {_ in g.next()} )
    }
    
    public static func encryptSymmetric(_ message: Data,
                                        using key: SymmetricKey,
                                        authenticating authenticatedData: Data) throws -> Data {
        return try ChaChaPoly.seal(message,
                                   using: key.key,
                                   authenticating: authenticatedData).combined
    }
    
    public static func decryptSymmetric(_ combined: Data,
                                        using key: SymmetricKey,
                                        authenticating authenticatedData: Data) throws -> Data {
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: combined),
                                   using: key.key,
                                   authenticating: authenticatedData)
    }
}

