//
//  MainWindow.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//

import Gtk

class MainWindow: ApplicationWindow {
    init(application: ApplicationRef,
         model: ApplicationModel) {
        super.init(ApplicationWindowRef(application: application).application_window_ptr)
        title = "Health Enclave Terminal"
        setDefaultSize(width: 720, height: 540)
        
        model.setupHotspot(started: { wc in
            self.page = ConnectPage(wifiConfiguration: wc)
        }, connected: {
            self.page = nil
        })
    }
    
    var page: Widget? {
        willSet {
            if let page = page {
                remove(widget: page)
            }
        }
        didSet {
            if let page = page {
                add(widget: page)
            }
        }
    }
}
