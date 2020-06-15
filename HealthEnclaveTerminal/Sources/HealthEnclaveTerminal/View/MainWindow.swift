//
//  MainWindow.swift
//  HealthEnclaveTerminal
//
//  Created by Lukas Schmierer on 04.03.20.
//
import Foundation
import Logging
import Gdk
import Gtk

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.MainWindow")

let keyBytesSize = 32

class MainWindow: ApplicationWindow {
    
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
    
    var sharedKeyBuffer = String()
    
    init(application: ApplicationProtocol, model: ApplicationModel) {
        self.model = model
        super.init(application: application)
        
        add(events: CInt(EventMask.key_press_mask.rawValue))
        connectKey(signal: "key_press_event") { _, event in
            let event = event._ptr.pointee
            
            if let scalar = UnicodeScalar(Gdk.keyvalToUnicode(keyval: event.keyval)),
                scalar != "\0" {
                self.onNewSharedKeyChar(char: Character(scalar))
            }
        }
        
        title = "Health Enclave Terminal"
        setDefaultSize(width: 720, height: 540)
        
        logger.debug("Showing LoadingPage...")
        page = LoadingPage()
        add(page!)
        
        do {
            try model.setupServer(
                onSetupComplete: { wc in
                    logger.debug("Showing ConnectPage...")
                    self.page = ConnectPage(wifiConfiguration: wc)
            },
                onDeviceConnected: {
                    self.page = SharedKeyPage()
            },
                onSharedKeySet: {
                    self.page = nil
            })
        } catch {
            logger.error("Can not create server: \(error)")
            application.quit()
        }
    }
    
    func onNewSharedKeyChar(char: Character) {
        sharedKeyBuffer.append(char)
        if(sharedKeyBuffer.count > 4 * (keyBytesSize / 3 + 1) /* size needed for base64 encdoing */) {
            sharedKeyBuffer.removeFirst()
        }
        
        if let key = Data(base64Encoded: String(sharedKeyBuffer)),
            key.count == keyBytesSize,
            self.page is SharedKeyPage {
            onNewSharedKey(key: key)
            
        }
    }
    
    func onNewSharedKey(key: Data) {
        model.setSharedKey(data: key)
    }
}
