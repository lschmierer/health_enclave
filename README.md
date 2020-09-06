# Health Enclave
Prototype of a fully decentralized EHR approach.
Documents are encrypted and stored on patient-controlled mobile devices.
The patient moves the mobile device between institutions for data transport.

## Health Enclave Terminal
The application requires a QR code scanner, that identifies itself as HID keyboard.
(Most scanners use US keyboard layout, configure your operating system accordingly.)

| Argument               | Description                                                                              |
|------------------------|------------------------------------------------------------------------------------------|
| -ssid <SSID>           | SSID for Clients to connect to. |
| -password <pw>         | Password of Wifi Network for Clients.                      |
| -interface <iface> | Network Interface to use. Default: "en0" on macOS, "wlan0" on Linux                          |
| -port <#port>          | Port to listen on. Default: 42242                                                        |
| -cert <cert.pem>       | PEM file containing TLS certificate chain. Required.                                     |
| -key <key.pem>         | PEM file containing TLS private key. Required.                                           |
| -practitioner <name>| Name of the practitioner. Used to tag documents.                |

Example usage:  `./HealthEnclaveTerminal -ssid SomeSSID -password SomePassword -cert cert.pem -key key.pem -practitioner PractitionerName`

### Build
Install prerequisites (see below).

From within the `HealthEnclaveTerminal` directory run `./build.sh` to build.

You can run the program using `.build/debug/HealthEnclaveTerminal`

Run `./xcodegen.sh` from within the `HealthEnclaveTerminal` directory to generate Xcode project files.

### Prerequisites
On Mac install Xcode from App Store and Homebrew from https://brew.sh

Make sure that the Xcode command line tools are set correctly
```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer/
```

#### Swift
Make sure Swift is installed and the executable is in your path.
You can download Swift from https://swift.org/download/.

The Terminal application requires Swift version 5.2.

`swift --version`, should give you something like
```
Apple Swift version 5.2.4 (swiftlang-1103.0.32.9 clang-1103.0.32.53)
Target: x86_64-apple-darwin19.5.0
```
on Mac and 
```
$ swift --version
Swift version 5.2.4 (swift-5.2.4-RELEASE)
Target: x86_64-unknown-linux-gnu
```
on Linux.

### Development Libraries
#### Mac
Using Homebrew
```
brew install gtk+3 glib gobject-introspection pkg-config qrencode adwaita-icon-theme
```

#### Ubuntu
```
sudo apt install libgtk-3-dev gir1.2-gtksource-3.0 gobject-introspection libgirepository1.0-dev libxml2-dev libqrencode-dev
```
## Health Enclave App
The App requires iOS 14 and Xcode 12.
