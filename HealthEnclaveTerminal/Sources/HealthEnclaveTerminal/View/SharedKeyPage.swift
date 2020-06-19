//
//  ConnectPage.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//
import Gtk

class SharedKeyPage: Box {    
    init() {
        super.init(orientation: .vertical, spacing: 60)
        
        let label = Label(str: "<span size='larger'>Please Scan <b>Shared Key</b></span>")
        label.useMarkup = true
        
        setValign(align: .center)
        add(label)
        showAll()
    }
}
