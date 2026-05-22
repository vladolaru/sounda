import AppKit
import Foundation
import SoundaCore

final class CursorTracker {
    typealias FrameHandler = (CursorFrame) -> Void

    private let framesPerSecond: TimeInterval
    private let onFrame: FrameHandler
    private var timer: Timer?
    private var previousSample: CursorSample?

    init(framesPerSecond: TimeInterval = 60, onFrame: @escaping FrameHandler) {
        self.framesPerSecond = framesPerSecond
        self.onFrame = onFrame
    }

    func start() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(
            withTimeInterval: 1 / framesPerSecond,
            repeats: true
        ) { [weak self] _ in
            self?.pollCursor()
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        pollCursor()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousSample = nil
    }
}

private struct CursorSample {
    var timestamp: Double
    var normalizedX: Double
    var normalizedY: Double
    var speed: Double
    var directionAngle: Double
}

private extension CursorTracker {
    func pollCursor() {
        let location = NSEvent.mouseLocation
        let timestamp = ProcessInfo.processInfo.systemUptime
        let normalizedLocation = normalize(location, in: screen(containing: location))
        let currentSample = sample(
            timestamp: timestamp,
            normalizedX: normalizedLocation.x,
            normalizedY: normalizedLocation.y
        )
        let acceleration = acceleration(for: currentSample)

        previousSample = currentSample
        onFrame(
            CursorFrame(
                timestamp: timestamp,
                normalizedX: currentSample.normalizedX,
                normalizedY: currentSample.normalizedY,
                speed: currentSample.speed,
                acceleration: acceleration,
                directionAngle: currentSample.directionAngle
            )
        )
    }

    func sample(timestamp: Double, normalizedX: Double, normalizedY: Double) -> CursorSample {
        guard let previousSample else {
            return CursorSample(
                timestamp: timestamp,
                normalizedX: normalizedX,
                normalizedY: normalizedY,
                speed: 0,
                directionAngle: 0
            )
        }

        let deltaTime = max(timestamp - previousSample.timestamp, .leastNonzeroMagnitude)
        let deltaX = normalizedX - previousSample.normalizedX
        let deltaY = normalizedY - previousSample.normalizedY
        let distance = hypot(deltaX, deltaY)

        return CursorSample(
            timestamp: timestamp,
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            speed: distance / deltaTime,
            directionAngle: atan2(deltaY, deltaX)
        )
    }

    func acceleration(for sample: CursorSample) -> Double {
        guard let previousSample else {
            return 0
        }

        let deltaTime = max(sample.timestamp - previousSample.timestamp, .leastNonzeroMagnitude)
        return (sample.speed - previousSample.speed) / deltaTime
    }

    func screen(containing location: NSPoint) -> NSScreen {
        NSScreen.screens.first { screen in
            screen.frame.contains(location)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func normalize(_ location: NSPoint, in screen: NSScreen) -> (x: Double, y: Double) {
        let frame = screen.frame
        let normalizedX = (location.x - frame.minX) / max(frame.width, .leastNonzeroMagnitude)
        let normalizedY = (location.y - frame.minY) / max(frame.height, .leastNonzeroMagnitude)

        return (
            x: clamp(Double(normalizedX), lower: 0, upper: 1),
            y: clamp(Double(normalizedY), lower: 0, upper: 1)
        )
    }

    func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
