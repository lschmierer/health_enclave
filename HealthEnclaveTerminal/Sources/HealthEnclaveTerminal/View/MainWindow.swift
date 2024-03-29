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
import CGLib

#if os(macOS)
import Combine
#else
import OpenCombine
#endif

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.MainWindow")

let keyBytesSize = 32


typealias ThreadCallback = () -> Bool

class ThreadCallbackHolder {
    public let call: ThreadCallback
    
    public init(_ closure: @escaping ThreadCallback) {
        self.call = closure
    }
}

func _threadsAddIdle(data: ThreadCallbackHolder, handler: @convention(c) @escaping (gpointer) -> gboolean) -> Int {
    let opaqueHolder = Unmanaged.passRetained(data).toOpaque()
    let callback = unsafeBitCast(handler, to: GSourceFunc.self)
    let rv = threadsAddIdleFull(priority: Int(G_PRIORITY_DEFAULT_IDLE), function: callback, data: opaqueHolder, notify: {
        if let swift = $0 {
            let holder = Unmanaged<ThreadCallbackHolder>.fromOpaque(swift)
            holder.release()
        }
    })
    return rv
}

func threadsAddIdle(callback: @escaping ThreadCallback) -> Int {
    let rv = _threadsAddIdle(data: ThreadCallbackHolder(callback)) {
        let holder = Unmanaged<ThreadCallbackHolder>.fromOpaque($0).takeUnretainedValue()
        let rv: gboolean = holder.call() ? 1 : 0
        return rv
    }
    return rv
}

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
    
    init(application: ApplicationRef, model: ApplicationModel) {
        self.model = model
        super.init(application: application)
        
        add(events: .keyPressMask)
        connectKey(signal: "key_press_event") { _, event in
            if let scalar = UnicodeScalar(keyvalToUnicode(keyval: Int(event.keyval))),
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
            .sink { [weak self] (result) in
                guard let self = self else { return }
                
                _ = threadsAddIdle {
                    switch result {
                    case let .success(wifiConfiguration):
                        logger.debug("Showing ConnectPage...")
                        self.page = ConnectPage(wifiConfiguration: wifiConfiguration)
                    case let .failure(error):
                        logger.error("Can not create server: \(error)")
                        application.quit()
                    }
                    return false
                }
        }
        
        serverDeviceConnectedSubscription = model.deviceConnectedSubject
            .sink { [weak self] in
                guard let self = self else { return }
                
                _ = threadsAddIdle {
                    logger.debug("Showing SharedKeyPage...")
                    self.page = SharedKeyPage()
                    return false
                }
        }
        
        serverSharedKeySetSubscription = model.sharedKeySetSubject
            .sink { [weak self] documentsModel in
                guard let self = self else { return }
                
                _ = threadsAddIdle {
                    logger.debug("Showing DocumentsPage...")
                    self.page = DocumentsPage(model: documentsModel, openUrl: self.openUrl)
                    return false
                }
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
    
    func openUrl(_ url: URL) {
        _ = try! showURIOnWindow(uri: url.absoluteString, timestamp: UInt32(Gdk.CURRENT_TIME))
    }
}
