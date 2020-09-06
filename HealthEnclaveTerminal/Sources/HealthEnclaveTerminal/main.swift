import Foundation
import Logging
import Gtk

LoggingSystem.bootstrap { label in
    var logHandler = StreamLogHandler.standardOutput(label: label)
    logHandler.logLevel = .debug
    return logHandler
}

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.main")

let applicationSupportDirectory = try! FileManager.default.url(for: .applicationSupportDirectory,
                                                               in: .userDomainMask,
                                                               appropriateFor: nil,
                                                               create: true).appendingPathComponent("HealthEnclaveTerminal", isDirectory: true)
if !FileManager.default.fileExists(atPath: applicationSupportDirectory.path) {
    try! FileManager.default.createDirectory(at: applicationSupportDirectory,
                                             withIntermediateDirectories: false,
                                             attributes: nil)
}
let cacheDirectory = try! FileManager.default.url(for: .cachesDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true).appendingPathComponent("HealthEnclaveTerminal", isDirectory: true)
if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
    try! FileManager.default.createDirectory(at: cacheDirectory,
                                             withIntermediateDirectories: false,
                                             attributes: nil)
}

logger.info("Setting up UserDefaults...")
UserDefaults.standard.register(defaults: [
    "hotspot": false,
    "ssid": "",
    "password": "",
    "port": 42242,
    "cert": "",
    "key": "",
    "practitioner": "",
])

#if os(macOS)
UserDefaults.standard.register(defaults: ["interface": "en0"])
#else
UserDefaults.standard.register(defaults: ["nterface": "wlan0"])
#endif

logger.info("Starting HelathEnclaveTerminal...")

logger.debug("Creating ApplicationModel...")
let appModel = ApplicationModel()

logger.debug("Running Gtk Application...")
let status = Application.run(id: "de.lschmierer.HealthEnclaveTerminal") { app in
    logger.debug("Showing MainWindow...")
    MainWindow(application: app, model: appModel).show()
}

logger.debug("Exiting Gtk Application...")

logger.debug("Clearing cache...")
if FileManager.default.fileExists(atPath: cacheDirectory.path) {
    try!FileManager.default.removeItem(at: cacheDirectory)
}
logger.debug("Cache cleared!")

guard let status = status else {
    fatalError("Could not create Gtk Application")
}
guard status == 0 else {
    fatalError("Application exited with status \(status)")
}
