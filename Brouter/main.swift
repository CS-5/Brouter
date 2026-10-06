import AppKit

if let status = CLI.runIfRequested(CommandLine.arguments) {
    exit(status)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
