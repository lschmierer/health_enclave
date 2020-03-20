//
//  CryptographicPrimitives.swift
//  
//
//  Created by Lukas Schmierer on 17.03.20.
//

import Sodium

public class CryptographicPrimitives {
    static let sodium = Sodium()

    public static func randomBytes(length: Int) -> Bytes {
        return sodium.randomBytes.buf(length: length)!
    }
}

