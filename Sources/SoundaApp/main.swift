import AppKit
import Foundation
import SoundaCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let arguments = Array(CommandLine.arguments.dropFirst())
let debugSampleLimit = cursorDebugSampleLimit(from: arguments)
var printedSamples = 0

let tracker = CursorTracker { frame in
    if let debugSampleLimit {
        printedSamples += 1
        print(
            String(
                format: "cursor x=%.3f y=%.3f speed=%.3f accel=%.3f dir=%.2f",
                frame.normalizedX,
                frame.normalizedY,
                frame.speed,
                frame.acceleration,
                frame.directionAngle
            )
        )

        if printedSamples >= debugSampleLimit {
            NSApplication.shared.terminate(nil)
        }
    }
}

print("Sounda starting...")
tracker.start()
app.run()

private func cursorDebugSampleLimit(from arguments: [String]) -> Int? {
    guard
        let flagIndex = arguments.firstIndex(of: "--cursor-debug-samples"),
        arguments.indices.contains(arguments.index(after: flagIndex)),
        let limit = Int(arguments[arguments.index(after: flagIndex)])
    else {
        return nil
    }

    return max(0, limit)
}
