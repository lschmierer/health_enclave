// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "HealthEnclaveTerminal",
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/rhx/SwiftGtk.git", .branch("master")),
        .package(url: "https://github.com/jedisct1/swift-sodium.git", from: "0.8.0"),
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
        .target(name: "HealthEnclaveTerminal", dependencies: [
            "Logging"
            "Gtk",
            "CQREncode",
            "Sodium",
            "HealthEnclaveCommon",
        ]),
    ]
)
