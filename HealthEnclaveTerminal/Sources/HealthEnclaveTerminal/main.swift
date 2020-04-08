import Foundation
import Logging
import Gtk

LoggingSystem.bootstrap { label in
    var logHandler = StreamLogHandler.standardOutput(label: label)
    logHandler.logLevel = .debug
    return logHandler
}

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.main")

logger.info("Setting up UserDefaults...")
UserDefaults.standard.register(defaults: [
    "hotspot": true,
    "ssid": "",
    "password": "",
    "port": 42242,
    "cert": "",
    "key": "",
])

#if os(macOS)
UserDefaults.standard.register(defaults: ["wifiInterface": "en0"])
#else
UserDefaults.standard.register(defaults: ["wifiInterface": "wlan0"])
#endif

logger.info("Starting HelathEnclaveTerminal...")

logger.debug("Creating ApplicationModel...")
guard let appModel = try? ApplicationModel() else {
    fatalError("Could not create ApplicationModel")
}

logger.debug("Running Gtk Application...")
let status = Application.run(id: "de.lschmierer.HealthEnclaveTerminal") { app in
    logger.debug("Showing MainWindow...")
    MainWindow(application: app, model: appModel).show()
}

guard let status = status else {
    fatalError("Could not create Gtk Application")
}
guard status == 0 else {
    fatalError("Application exited with status \(status)")
}
