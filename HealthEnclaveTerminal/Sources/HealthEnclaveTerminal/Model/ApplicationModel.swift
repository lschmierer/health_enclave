//
//  ApplicationModel.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//

import Dispatch

class ApplicationModel {
    func setupHotspot(
        started: @escaping (_ wifiConfiguration: String) -> Void,
        connected: @escaping () -> Void
    ) {
        started("Wifi Configuration")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            connected()
        }
    }
}
