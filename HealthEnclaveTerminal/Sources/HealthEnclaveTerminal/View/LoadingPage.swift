//
//  LoadingPage.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 17.03.20.
//

import Gtk

class LoadingPage: Box {
    init() {
        super.init(BoxRef(orientation: .vertical, spacing: 60).box_ptr)
        
        let spinner = Spinner()
        spinner.setSizeRequest(width: 100, height: 100)
        spinner.start()
        
        setValign(align: .center)
        add(widget: spinner)
        showAll()
    }
}
