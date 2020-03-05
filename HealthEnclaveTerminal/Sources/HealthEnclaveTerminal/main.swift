import Gtk

import HealthEnclaveCommon

let status = Application.run(id: "de.lschmierer.HealthEnclaveTerminal") { app in
    let appModel = ApplicationModel()
    MainWindow(application: app, model: appModel).showAll()
}

guard let status = status else {
    fatalError("Could not create Application")
}
guard status == 0 else {
    fatalError("Application exited with status \(status)")
}
