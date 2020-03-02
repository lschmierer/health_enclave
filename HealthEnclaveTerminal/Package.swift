// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "HealthEnclaveTerminal",
    dependencies: [
        .package(url: "https://github.com/rhx/SwiftGtk.git", .branch("master")),
        .package(path: "../HealthEnclaveCommon"),
    ],
    targets: [
        .target(name: "HealthEnclaveTerminal", dependencies: ["Gtk", "HealthEnclaveCommon"]),
    ]
)
