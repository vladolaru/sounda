import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--self-test") {
    Foundation.exit(DiagnosticsRunner().runSelfTest())
}

if arguments.contains("--pointer-smoke") {
    Foundation.exit(DiagnosticsRunner().runPointerSmoke())
}

if let screenSamplerBenchmarkDuration = screenSamplerBenchmarkDuration(from: arguments) {
    Foundation.exit(ScreenSamplerBenchmarkRunner().run(duration: screenSamplerBenchmarkDuration))
}

if let pointerMelodyDemo = pointerMelodyDemo(from: arguments) {
    Foundation.exit(
        DiagnosticsRunner().runPointerMelodyDemo(
            duration: pointerMelodyDemo.duration,
            style: pointerMelodyDemo.style
        )
    )
}

let app = NSApplication.shared
let delegate = AppDelegate(arguments: arguments)
app.delegate = delegate
app.run()

private struct PointerMelodyDemo {
    let duration: TimeInterval
    let style: PointerMelodyDemoStyle
}

private func pointerMelodyDemo(from arguments: [String]) -> PointerMelodyDemo? {
    guard let flagIndex = arguments.firstIndex(where: { argument in
        argument == "--pointer-melody-demo" ||
            argument == "--pointer-ode-demo" ||
            argument == "--pointer-entertainer-demo"
    }) else {
        return nil
    }

    let style: PointerMelodyDemoStyle = arguments[flagIndex] == "--pointer-entertainer-demo" ? .entertainer : .odeToJoy
    let valueIndex = arguments.index(after: flagIndex)
    guard
        arguments.indices.contains(valueIndex),
        !arguments[valueIndex].hasPrefix("--"),
        let duration = TimeInterval(arguments[valueIndex])
    else {
        return PointerMelodyDemo(duration: 30, style: style)
    }

    return PointerMelodyDemo(duration: duration, style: style)
}

private func screenSamplerBenchmarkDuration(from arguments: [String]) -> TimeInterval? {
    guard let flagIndex = arguments.firstIndex(of: "--screen-sampler-benchmark") else {
        return nil
    }

    let valueIndex = arguments.index(after: flagIndex)
    guard
        arguments.indices.contains(valueIndex),
        !arguments[valueIndex].hasPrefix("--"),
        let duration = TimeInterval(arguments[valueIndex])
    else {
        return 4
    }

    return duration
}
