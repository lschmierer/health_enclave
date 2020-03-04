# Health Enclave
## Build the Terminal App
Install prerequisites (see below).

From within the `HealthEnclaveTerminal` directory run `./build.sh` to build.

You can run the program using `.build/debug/HealthEnclaveTerminal`

Run `./xcodegen.sh` from within the `HealthEnclaveTerminal` directory to generate Xcode project files.

## Prerequisites
On Mac install Xcode from App Store and Homebrew from https://brew.sh

### Swift
Make sure Swift is installed and the executable is in your path.
You can download Swift from https://swift.org/download/.

`swift --version`, should give you something like
```
$ swift --version
Apple Swift version 5.1.3 (swiftlang-1100.0.282.1 clang-1100.0.33.15)
Target: x86_64-apple-darwin19.3.0
```
on Mac and 
```
$ swift --version
Swift version 5.1.4 (swift-5.1.4-RELEASE)
Target: x86_64-unknown-linux-gnu
```
on Linux.

## Development Libraries
### Mac
Using Homebrew
```
brew install gtk+3 gobject-introspection pkg-config
```

### Ubuntu
```
sudo apt install libgtk-3-dev gir1.2-gtksource-3.0 gobject-introspection libgirepository1.0-dev libxml2-dev
```
