//
//  ConnectPage.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//
import Foundation
import Gtk

class ConnectPage: Box {
    init(wifiConfiguration: String) {
        super.init(orientation: .vertical, spacing: 60)
        
        let qrCode = QRCode(data: wifiConfiguration)
        qrCode.setSizeRequest(width: 200, height: 200)
        
        let label = Label(str: "<span size='larger'>Please Scan QR Code with Health Enclave App</span>")
        label.useMarkup = true
        
        setValign(align: .center)
        add(widgets: [qrCode, label])
        showAll()
    }
}
