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
    init(application: ApplicationProtocol, model: ApplicationModel) {
        self.model = model
        super.init(application: application)
        title = "Health Enclave Terminal"
        setDefaultSize(width: 720, height: 540)
        
        logger.debug("Showing LoadingPage...")
        page = LoadingPage()
        add(page!)
        
        do {
            try model.setupServer(created: { wc in
                logger.debug("Showing ConnectPage...")
                self.page = ConnectPage(wifiConfiguration: wc)
            }, connected: {
                self.page = nil
            })
        } catch {
            logger.error("Can not create server")
        }
        
        
        connect(signal: .destroy) {
            model.shutdownServer()
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
