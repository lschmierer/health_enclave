//
//  CryptoPrimitives.swift
//  
//
//  Created by Lukas Schmierer on 17.03.20.
//
import Crypto

public class CryptoPrimitives {

    public static func randomBytes(count: Int) -> [UInt8] {
        // SystemRandomNumberGenerator is cryptographically secure.
        // Uses arc4random_buf(3) on Apple platforms,
        //      getrandom(2) on Linux platforms when available; otherwise, /dev/urandom and
        //      BCryptGenRandom on Windows.
        var g = SystemRandomNumberGenerator()
        return (0..<count).map( {_ in g.next()} )
    }
}

