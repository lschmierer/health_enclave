//
//  KeyChain.swift
//  HealthEnclaveApp
//
//  Created by Lukas Schmierer on 06.07.20.
//  Copyright © 2020 Lukas Schmierer. All rights reserved.
//
import Foundation
import Security

import HealthEnclaveCommon

let deviceKeyKey = "DeviceKey"

extension OSStatus: Error {}

class KeyChain {
    static func save(key: DeviceCryptography.DeviceKey) throws {
        let query = [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrAccount as String: deviceKeyKey,
            kSecValueData as String: key.data] as [String : Any]

        SecItemDelete(query as CFDictionary)

        let status: OSStatus = SecItemAdd(query as CFDictionary, nil)
        
        if status != noErr {
            throw status
        }
    }

    static func load() -> DeviceCryptography.DeviceKey? {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: deviceKeyKey,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne ] as [String : Any]

        var dataTypeRef: AnyObject? = nil

        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == noErr, let data = dataTypeRef as! Data? {
            return try! DeviceCryptography.DeviceKey(data: data)
        } else {
            return nil
        }
    }
}
