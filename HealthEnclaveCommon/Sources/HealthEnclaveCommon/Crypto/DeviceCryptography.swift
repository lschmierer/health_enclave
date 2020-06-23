//
//  DeviceCryptography.swift
//  
//
//  Created by Lukas Schmierer on 23.06.20.
//

import Foundation

extension HealthEnclave_DeviceIdentifier {
    public static func random() -> HealthEnclave_DeviceIdentifier {
        return HealthEnclave_DeviceIdentifier.with {
            $0.data = Data(CryptoPrimitives.randomBytes(count: 256))
        }
    }
}

public enum DeviceCryptography {
}
