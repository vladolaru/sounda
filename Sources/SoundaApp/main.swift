import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--self-test") {
    Foundation.exit(DiagnosticsRunner().runSelfTest())
}

if arguments.contains("--pointer-smoke") {
    Foundation.exit(DiagnosticsRunner().runPointerSmoke())
}

let app = NSApplication.shared
let delegate = AppDelegate(arguments: arguments)
app.delegate = delegate
app.run()
