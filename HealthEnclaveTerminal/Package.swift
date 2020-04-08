// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "HealthEnclaveTerminal",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(name: "Gtk", url: "https://github.com/rhx/SwiftGtk.git", .branch("master")),
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
            .product(name: "Logging", package: "swift-log"),
            "Gtk",
            "HealthEnclaveCommon",
            "CQREncode",
        ]),
    ]
)
