import Logging
import Gtk

import HealthEnclaveCommon

LoggingSystem.bootstrap { label in
    var logHandler = StreamLogHandler.standardOutput(label: label)
    logHandler.logLevel = .debug
    return logHandler
}

private let logger = Logger(label: "de.lschmierer.HealthEnvlaveTerminal.main")

logger.info("Starting HelathEnclaveTerminal...")

logger.debug("Creating ApplicationModel...")
let appModel = ApplicationModel()

logger.debug("Running Gtk Application...")
let status = Application.run(id: "de.lschmierer.HealthEnclaveTerminal") { app in
    logger.debug("Showing MainWindow...")
    MainWindow(application: app, model: appModel).show()
}

guard let status = status else {
    fatalError("Could not create Application")
}
guard status == 0 else {
    fatalError("Application exited with status \(status)")
}
