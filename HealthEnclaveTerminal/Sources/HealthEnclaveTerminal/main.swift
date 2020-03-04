import Gtk

import HealthEnclaveCommon

let status = Application.run { app in
    let window = ApplicationWindowRef(application: app)
    window.title = "Health Enclave Terminal"
    window.setDefaultSize(width: 720, height: 540)
    let qrCode = QRCode(data: "Test")
    window.add(widget: qrCode)
    window.showAll()
}

guard let status = status else {
    fatalError("Could not create Application")
}
guard status == 0 else {
    fatalError("Application exited with status \(status)")
}
