import AppKit
import Darwin
import Foundation
import SoundaCore

enum PointerMelodyDemoStyle {
    case odeToJoy
    case entertainer

    var displayName: String {
        switch self {
        case .odeToJoy:
            return "funky Ode-style"
        case .entertainer:
            return "ragtime Entertainer-style"
        }
    }
}

struct DiagnosticsRunner {
    func runSelfTest() -> Int32 {
        var mapper = SoundMapper(settings: .default)
        let audioEngine = AudioEngineController()
        let segments = SelfTestSegment.all
        var didFail = false

        print("Sounda self-test starting...")

        for segment in segments {
            let states = segment.frames.map { mapper.map($0) }
            let metrics = audioEngine.renderDebugMetrics(for: states)
            let result = segment.validate(states, metrics)

            print(
                String(
                    format: "%@: %@ rms=%.5f peak=%.5f accentPeak=%.5f",
                    segment.name,
                    result.status,
                    metrics.rms,
                    metrics.peak,
                    metrics.accentPeak
                )
            )

            if !result.passed {
                didFail = true
                print("  \(result.message)")
            }
        }

        if didFail {
            print("Sounda self-test failed")
            return 1
        }

        print("Sounda self-test passed")
        return 0
    }

    func runPointerSmoke() -> Int32 {
        guard CGPreflightPostEventAccess() else {
            print("Pointer smoke skipped: macOS has not granted permission to post input events.")
            return 0
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let source else {
            print("Pointer smoke skipped: unable to create a Core Graphics event source.")
            return 0
        }

        let current = NSEvent.mouseLocation
        let path = [
            current,
            CGPoint(x: current.x + 10, y: current.y),
            CGPoint(x: current.x + 10, y: current.y + 10),
            current,
        ]

        for point in path {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                print("Pointer smoke skipped: unable to create a mouse movement event.")
                return 0
            }

            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.04)
        }

        print("Pointer smoke posted a small opt-in mouse movement sequence.")
        return 0
    }

    func runPointerMelodyDemo(
        duration requestedDuration: TimeInterval,
        style: PointerMelodyDemoStyle = .odeToJoy
    ) -> Int32 {
        guard requestedDuration.isFinite else {
            print("Pointer melody demo failed: duration must be a finite number.")
            return 1
        }

        let duration = clampedDemoDuration(requestedDuration)
        let canPostEvents = CGPreflightPostEventAccess()
        let source = canPostEvents ? CGEventSource(stateID: .hidSystemState) : nil
        let originalLocation = NSEvent.mouseLocation
        let screen = screen(containing: originalLocation)
        let companionPID = runningSoundaAppPID()

        print(String(format: "Sounda %@ pointer demo starting for %.1f seconds...", style.displayName, duration))
        print("The demo moves only the cursor, never clicks. Press Control-Option-Command-Q to quit Sounda and stop the demo early.")
        if !canPostEvents {
            print("Input event posting is not permitted; using direct cursor warp fallback.")
        }

        defer {
            glidePointer(
                from: NSEvent.mouseLocation,
                to: originalLocation,
                duration: 0.65,
                source: source,
                screen: screen
            )
        }

        if companionPID == nil {
            print("No separate running SoundaApp process was found; pointer movement will still run, but it may be silent.")
        }

        let frameRate = 60.0
        let frameCount = max(1, Int(duration * frameRate))
        let startTime = ProcessInfo.processInfo.systemUptime

        for frameIndex in 0...frameCount {
            if let companionPID, !isProcessRunning(companionPID) {
                print("Sounda quit detected; stopping pointer demo.")
                return 0
            }

            let progress = Double(frameIndex) / Double(frameCount)
            movePointer(
                to: melodyPoint(progress: progress, screen: screen, style: style),
                source: source,
                screen: screen
            )

            let targetTime = startTime + (Double(frameIndex + 1) / frameRate)
            let sleepDuration = targetTime - ProcessInfo.processInfo.systemUptime
            if sleepDuration > 0 {
                Thread.sleep(forTimeInterval: sleepDuration)
            }
        }

        print("Sounda \(style.displayName) pointer demo complete.")
        return 0
    }
}

private struct SelfTestSegment {
    let name: String
    let frames: [CursorFrame]
    let validate: ([SoundState], AudioDebugMetrics) -> DiagnosticResult

    static let all: [SelfTestSegment] = [
        SelfTestSegment(
            name: "slow replay",
            frames: makeFrames(
                startTime: 0,
                count: 8,
                normalizedX: { 0.20 + Double($0) * 0.002 },
                normalizedY: { _ in 0.45 },
                speed: { _ in 0.04 },
                acceleration: { _ in 0.01 },
                directionAngle: { _ in 0 }
            ),
            validate: { states, metrics in
                let reportsSilence = states.allSatisfy(\.isSilent)
                let isQuiet = metrics.peak < 0.001 && metrics.rms < 0.001
                return DiagnosticResult(
                    passed: reportsSilence && isQuiet,
                    status: reportsSilence && isQuiet ? "PASS silence" : "FAIL expected silence",
                    message: "Expected slow movement to stay silent."
                )
            }
        ),
        SelfTestSegment(
            name: "fast horizontal replay",
            frames: makeFrames(
                startTime: 1,
                count: 10,
                normalizedX: { 0.10 + Double($0) * 0.08 },
                normalizedY: { _ in 0.55 },
                speed: { _ in 0.82 },
                acceleration: { _ in 0.20 },
                directionAngle: { _ in 0 }
            ),
            validate: { states, metrics in
                let hasAudibleState = states.contains { !$0.isSilent && $0.amplitude > 0.01 }
                let hasAudio = metrics.peak > 0.01 && metrics.rms > 0.001
                return DiagnosticResult(
                    passed: hasAudibleState && hasAudio,
                    status: hasAudibleState && hasAudio ? "PASS audible" : "FAIL expected audio",
                    message: "Expected fast movement to produce non-zero generated audio."
                )
            }
        ),
        SelfTestSegment(
            name: "sharp-turn replay",
            frames: makeFrames(
                startTime: 2,
                count: 10,
                normalizedX: { 0.55 + Double($0) * 0.01 },
                normalizedY: { _ in 0.70 },
                speed: { _ in 0.78 },
                acceleration: { _ in 0.90 },
                directionAngle: { index in index < 4 ? 0 : Double.pi }
            ),
            validate: { states, metrics in
                let hasAccentState = states.contains { $0.accentTriggered }
                let hasAccentAudio = metrics.accentPeak > 0.01
                return DiagnosticResult(
                    passed: hasAccentState && hasAccentAudio,
                    status: hasAccentState && hasAccentAudio ? "PASS accent" : "FAIL expected accent",
                    message: "Expected a sharp direction change to trigger chime/accent activity."
                )
            }
        ),
    ]
}

private struct DiagnosticResult {
    let passed: Bool
    let status: String
    let message: String
}

private func makeFrames(
    startTime: Double,
    count: Int,
    normalizedX: (Int) -> Double,
    normalizedY: (Int) -> Double,
    speed: (Int) -> Double,
    acceleration: (Int) -> Double,
    directionAngle: (Int) -> Double
) -> [CursorFrame] {
    (0..<count).map { index in
        CursorFrame(
            timestamp: startTime + Double(index) * 0.08,
            normalizedX: normalizedX(index),
            normalizedY: normalizedY(index),
            speed: speed(index),
            acceleration: acceleration(index),
            directionAngle: directionAngle(index)
        )
    }
}

private struct MelodyStep {
    let noteIndex: Int
    let beats: Double
    let accent: Bool
}

private let odeToJoyFunkSteps: [MelodyStep] = [
    MelodyStep(noteIndex: 2, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 3, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 4, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 4, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 3, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.75, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.25, accent: true),
    MelodyStep(noteIndex: 1, beats: 1.00, accent: false),

    MelodyStep(noteIndex: 2, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 3, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 4, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 4, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 3, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 1, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 0, beats: 1.00, accent: false),

    MelodyStep(noteIndex: 1, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 3, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 0, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 3, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.50, accent: false),

    MelodyStep(noteIndex: 2, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 3, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 4, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 4, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 3, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 2, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 1, beats: 0.50, accent: true),
    MelodyStep(noteIndex: 0, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 0, beats: 1.50, accent: true),
]

private let entertainerFunkSteps: [MelodyStep] = [
    MelodyStep(noteIndex: 8, beats: 0.35, accent: true),
    MelodyStep(noteIndex: 9, beats: 0.35, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.35, accent: true),
    MelodyStep(noteIndex: 5, beats: 0.70, accent: true),
    MelodyStep(noteIndex: 5, beats: 0.20, accent: false),
    MelodyStep(noteIndex: 6, beats: 0.25, accent: true),
    MelodyStep(noteIndex: 4, beats: 0.85, accent: false),
    MelodyStep(noteIndex: 1, beats: 0.25, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.25, accent: false),

    MelodyStep(noteIndex: 2, beats: 0.45, accent: true),
    MelodyStep(noteIndex: 7, beats: 0.35, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.35, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.55, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.90, accent: true),
    MelodyStep(noteIndex: 7, beats: 0.22, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.22, accent: true),
    MelodyStep(noteIndex: 8, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 9, beats: 0.25, accent: true),
    MelodyStep(noteIndex: 9, beats: 0.35, accent: true),
    MelodyStep(noteIndex: 7, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 8, beats: 0.30, accent: true),
    MelodyStep(noteIndex: 9, beats: 0.55, accent: false),
    MelodyStep(noteIndex: 9, beats: 0.22, accent: true),
    MelodyStep(noteIndex: 6, beats: 0.35, accent: false),
    MelodyStep(noteIndex: 8, beats: 0.80, accent: true),
    MelodyStep(noteIndex: 7, beats: 1.10, accent: true),
    MelodyStep(noteIndex: 1, beats: 0.25, accent: false),
    MelodyStep(noteIndex: 2, beats: 0.25, accent: true),

    MelodyStep(noteIndex: 2, beats: 0.45, accent: true),
    MelodyStep(noteIndex: 7, beats: 0.35, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.35, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.75, accent: true),
    MelodyStep(noteIndex: 2, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.50, accent: false),
    MelodyStep(noteIndex: 3, beats: 0.30, accent: true),
    MelodyStep(noteIndex: 5, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.40, accent: true),
    MelodyStep(noteIndex: 9, beats: 0.55, accent: false),
    MelodyStep(noteIndex: 9, beats: 0.25, accent: true),
    MelodyStep(noteIndex: 8, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 7, beats: 0.30, accent: true),
    MelodyStep(noteIndex: 5, beats: 0.70, accent: false),
    MelodyStep(noteIndex: 8, beats: 1.00, accent: true),

    MelodyStep(noteIndex: 9, beats: 0.35, accent: true),
    MelodyStep(noteIndex: 7, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 8, beats: 0.30, accent: true),
    MelodyStep(noteIndex: 9, beats: 0.55, accent: false),
    MelodyStep(noteIndex: 9, beats: 0.30, accent: true),
    MelodyStep(noteIndex: 7, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 8, beats: 0.30, accent: true),
    MelodyStep(noteIndex: 7, beats: 0.55, accent: false),
    MelodyStep(noteIndex: 9, beats: 0.35, accent: true),
    MelodyStep(noteIndex: 7, beats: 0.30, accent: false),
    MelodyStep(noteIndex: 8, beats: 0.30, accent: true),
    MelodyStep(noteIndex: 9, beats: 0.55, accent: false),
    MelodyStep(noteIndex: 9, beats: 0.22, accent: true),
    MelodyStep(noteIndex: 6, beats: 0.35, accent: false),
    MelodyStep(noteIndex: 8, beats: 0.80, accent: true),
    MelodyStep(noteIndex: 7, beats: 1.20, accent: true),
]

private func melodyPoint(
    progress rawProgress: Double,
    screen: NSScreen,
    style: PointerMelodyDemoStyle
) -> CGPoint {
    let progress = clamp(rawProgress, lower: 0, upper: 1)
    let steps = stepsForMelody(style)
    let totalBeats = steps.reduce(0) { $0 + $1.beats }
    let songPosition = min(progress * totalBeats, totalBeats - .leastNonzeroMagnitude)

    var accumulatedBeats = 0.0
    var stepIndex = 0
    for candidateIndex in steps.indices {
        let nextBeat = accumulatedBeats + steps[candidateIndex].beats
        if songPosition < nextBeat {
            stepIndex = candidateIndex
            break
        }

        accumulatedBeats = nextBeat
    }

    let step = steps[stepIndex]
    let nextStep = steps[min(stepIndex + 1, steps.count - 1)]
    let localBeat = (songPosition - accumulatedBeats) / max(step.beats, .leastNonzeroMagnitude)
    let transition = smoothstep((localBeat - transitionStart(for: style)) / transitionWidth(for: style))
    let noteIndex = Double(step.noteIndex) + (Double(nextStep.noteIndex - step.noteIndex) * transition)
    let noteFlutter = sin(progress * Double.pi * 2 * totalBeats * 2.0) * noteFlutterAmount(for: style)
    let accentSlide = step.accent ? sin(Double.pi * min(localBeat * 2.0, 1)) * accentSlideAmount(for: style) : 0
    let x = clamp(noteIndex / 10 + noteFlutter + accentSlide, lower: 0.02, upper: 0.92)

    let beatWave = sin(progress * Double.pi * 2 * totalBeats)
    let offbeatWave = sin(progress * Double.pi * 2 * totalBeats * 2.0 + Double.pi * 0.35)
    let accentKick = step.accent ? sin(Double.pi * min(localBeat * 2.4, 1)) * accentKickAmount(for: style) : 0
    let phraseLift = sin(progress * Double.pi * 2 * 4) * phraseLiftAmount(for: style)
    let y = clamp(
        baseHeight(for: style) + beatWave * beatWaveAmount(for: style) + offbeatWave * offbeatWaveAmount(for: style) + phraseLift + accentKick,
        lower: 0.20,
        upper: 0.84
    )

    return point(normalizedX: x, normalizedY: y, screen: screen)
}

private func stepsForMelody(_ style: PointerMelodyDemoStyle) -> [MelodyStep] {
    switch style {
    case .odeToJoy:
        return odeToJoyFunkSteps
    case .entertainer:
        return entertainerFunkSteps
    }
}

private func transitionStart(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.58
    case .entertainer:
        return 0.34
    }
}

private func transitionWidth(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.42
    case .entertainer:
        return 0.28
    }
}

private func noteFlutterAmount(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.005
    case .entertainer:
        return 0.012
    }
}

private func accentSlideAmount(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.040
    case .entertainer:
        return 0.065
    }
}

private func accentKickAmount(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.10
    case .entertainer:
        return 0.16
    }
}

private func phraseLiftAmount(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.055
    case .entertainer:
        return 0.075
    }
}

private func beatWaveAmount(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.12
    case .entertainer:
        return 0.16
    }
}

private func offbeatWaveAmount(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.065
    case .entertainer:
        return 0.10
    }
}

private func baseHeight(for style: PointerMelodyDemoStyle) -> Double {
    switch style {
    case .odeToJoy:
        return 0.50
    case .entertainer:
        return 0.48
    }
}

private func movePointer(to point: CGPoint, source: CGEventSource?, screen: NSScreen) {
    let quartzPoint = quartzPoint(fromAppKitPoint: point, screen: screen)

    if let source,
       let event = CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: quartzPoint,
        mouseButton: .left
       ) {
        event.post(tap: .cghidEventTap)
        return
    }

    CGWarpMouseCursorPosition(quartzPoint)
}

private func glidePointer(
    from startPoint: CGPoint,
    to endPoint: CGPoint,
    duration: TimeInterval,
    source: CGEventSource?,
    screen: NSScreen
) {
    let steps = max(1, Int(duration * 60))

    for index in 0...steps {
        let progress = smoothstep(Double(index) / Double(steps))
        let point = CGPoint(
            x: startPoint.x + (endPoint.x - startPoint.x) * progress,
            y: startPoint.y + (endPoint.y - startPoint.y) * progress
        )
        movePointer(to: point, source: source, screen: screen)
        Thread.sleep(forTimeInterval: duration / Double(steps))
    }
}

private func quartzPoint(fromAppKitPoint point: CGPoint, screen: NSScreen) -> CGPoint {
    let appKitFrame = screen.frame
    let normalizedX = CGFloat(
        clamp(
            Double((point.x - appKitFrame.minX) / max(appKitFrame.width, .leastNonzeroMagnitude)),
            lower: 0,
            upper: 1
        )
    )
    let normalizedY = CGFloat(
        clamp(
            Double((point.y - appKitFrame.minY) / max(appKitFrame.height, .leastNonzeroMagnitude)),
            lower: 0,
            upper: 1
        )
    )

    guard let displayID = displayID(for: screen) else {
        let yWithinScreen = point.y - appKitFrame.minY
        return CGPoint(
            x: point.x,
            y: appKitFrame.minY + appKitFrame.height - yWithinScreen
        )
    }

    let quartzBounds = CGDisplayBounds(displayID)

    return CGPoint(
        x: quartzBounds.minX + normalizedX * quartzBounds.width,
        y: quartzBounds.minY + (1 - normalizedY) * quartzBounds.height
    )
}

private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
}

private func point(normalizedX: Double, normalizedY: Double, screen: NSScreen) -> CGPoint {
    let frame = screen.frame
    return CGPoint(
        x: frame.minX + CGFloat(clamp(normalizedX, lower: 0, upper: 1)) * frame.width,
        y: frame.minY + CGFloat(clamp(normalizedY, lower: 0, upper: 1)) * frame.height
    )
}

private func screen(containing location: CGPoint) -> NSScreen {
    NSScreen.screens.first { screen in
        screen.frame.contains(location)
    } ?? NSScreen.main ?? NSScreen.screens[0]
}

private func runningSoundaAppPID() -> pid_t? {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    return NSWorkspace.shared.runningApplications.first { app in
        app.processIdentifier != currentPID &&
            (app.executableURL?.lastPathComponent == "SoundaApp" || app.localizedName == "SoundaApp")
    }?.processIdentifier
}

private func isProcessRunning(_ pid: pid_t) -> Bool {
    Darwin.kill(pid, 0) == 0
}

private func smoothstep(_ value: Double) -> Double {
    let clamped = clamp(value, lower: 0, upper: 1)
    return clamped * clamped * (3 - 2 * clamped)
}

private func clampedDemoDuration(_ duration: TimeInterval) -> TimeInterval {
    return min(max(duration, 1), 60)
}

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}
