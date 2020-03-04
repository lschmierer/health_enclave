// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "HealthEnclaveTerminal",
    dependencies: [
        .package(url: "https://github.com/rhx/SwiftGtk.git", .branch("master")),
        .package(path: "../HealthEnclaveCommon"),
    ],
    targets: [
        .systemLibrary(
            name: "CQREncode",
            pkgConfig: "libqrencode",
            providers: [
                .brew(["qrencode"]),
                .apt(["libqrencode-dev"])
            ]
        ),
        .target(name: "HealthEnclaveTerminal", dependencies: ["Gtk", "CQREncode", "HealthEnclaveCommon"]),
    ]
)
