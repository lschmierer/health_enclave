//
//  CryptoPrimitives.swift
//  
//
//  Created by Lukas Schmierer on 17.03.20.
//
import Foundation
import Crypto

public enum CryptoError: Error {
    case invalidSize(Int)
}

public enum CryptoPrimitives {
    public class SymmetricKey {
        let key: Crypto.SymmetricKey
        
        public var data: Data {
            get {
                return key.withUnsafeBytes { Data($0) }
            }
        }
        
        public init() {
            key = Crypto.SymmetricKey(size: .bits256)
        }
        
        public init(data: Data) throws {
            key = Crypto.SymmetricKey(data: data)
            if key.bitCount != 256 {
                throw CryptoError.invalidSize(key.bitCount)
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
    
    public static func hash(_ data: Data) -> Data {
        return Data(SHA256.hash(data: data))
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

