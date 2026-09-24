import AppKit
import Darwin

let arguments = CommandLine.arguments
if arguments.contains("--dump") {
    print(BluetoothStatusReader.dump())
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
