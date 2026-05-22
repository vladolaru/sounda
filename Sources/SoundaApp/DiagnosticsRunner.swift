import AppKit
import Foundation
import SoundaCore

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
