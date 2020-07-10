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

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.MainWindow")

let keyBytesSize = 32

class MainWindow: ApplicationWindow {
    private let model: ApplicationModel
    private var serverSetupCompleteSubscription: Cancellable?
    private var serverDeviceConnectedSubscription: Cancellable?
    private var serverSharedKeySetSubscription: Cancellable?
    
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
        
        add(events: .keyPressMask)
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
        
        serverSetupCompleteSubscription = model.setupCompletedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (result) in
                switch result {
                case let .success(wifiConfiguration):
                    logger.debug("Showing ConnectPage...")
                    self?.page = ConnectPage(wifiConfiguration: wifiConfiguration)
                case let .failure(error):
                    logger.error("Can not create server: \(error)")
                    application.quit()
                }
        }
        
        serverDeviceConnectedSubscription = model.deviceConnectedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                logger.debug("Showing SharedKeyPage...")
                self?.page = SharedKeyPage()
        }
        
        serverSharedKeySetSubscription = model.sharedKeySetSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] documentsModel in
                logger.debug("Showing DocumentsPage...")
                self?.page = DocumentsPage(model: documentsModel)
        }
        
        model.setupServer()
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
        do {
            try model.setSharedKey(data: key)
        } catch {
            logger.error("Error setting shared key: \(error)")
        }
    }
}
