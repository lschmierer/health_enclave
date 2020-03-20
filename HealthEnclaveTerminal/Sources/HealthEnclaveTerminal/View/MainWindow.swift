//
//  MainWindow.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//
import Logging
import Gtk

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.MainWindow")

class MainWindow: ApplicationWindow {
    init(application: ApplicationRef,
         model: ApplicationModel) {
        self.model = model
        super.init(ApplicationWindowRef(application: application).application_window_ptr)
        title = "Health Enclave Terminal"
        setDefaultSize(width: 720, height: 540)
        
        logger.debug("Showing LoadingPage...")
        page = LoadingPage()
        add(page!)
        
        model.createHotspot(created: { wc in
            logger.debug("Showing ConnectPage...")
            self.page = ConnectPage(wifiConfiguration: wc)
        }, connected: {
            self.page = nil
        })
        
        connect(signal: .destroy) {
            model.shutdownHotspot()
        }
    }
    
    let model: ApplicationModel
    
    var page: Widget? {
        willSet {
            if let page = page {
                remove(widget: page)
            }
        }
        didSet {
            if let page = page {
                add(widget: page)
                show()
            }
        }
    }
}
