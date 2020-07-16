//
//  LoadingPage.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 17.03.20.
//

import Gtk

class LoadingPage: Box {
     init() {
        super.init(orientation: .vertical, spacing: 60)
        
        let spinner = Spinner()
        spinner.setSizeRequest(width: 100, height: 100)
        spinner.start()
        
        setValign(align: .center)
        add(spinner)
        showAll()
    }
}
