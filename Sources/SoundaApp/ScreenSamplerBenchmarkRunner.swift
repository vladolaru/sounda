import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import SoundaCore

struct ScreenSamplerBenchmarkRunner {
    func run(duration requestedDuration: TimeInterval) -> Int32 {
        guard requestedDuration.isFinite else {
            print("Screen sampler benchmark failed: duration must be a finite number.")
            return 1
        }

        let duration = min(max(requestedDuration, 1), 12)
        print(String(format: "Sounda screen sensor benchmark starting: %.1fs per capture mode", duration))
        print("No frames are recorded, saved, or previewed; each sample is reduced to synthetic numbers and discarded.")

        runSyntheticReducerBenchmark(duration: duration)

        guard CGPreflightScreenCaptureAccess() else {
            print("ScreenCaptureKit benchmark skipped: Screen Recording permission is not granted to this terminal.")
            return 1
        }

        let result = runAsync {
            try await runScreenCaptureKitBenchmarks(duration: duration)
        }

        switch result {
        case .success:
            return 0
        case .failure(let error):
            print("ScreenCaptureKit benchmark failed: \(error.localizedDescription)")
            return 1
        }
    }
}

private struct BenchmarkConfiguration {
    var name: String
    var framesPerSecond: Int
    var cropSize: CGFloat
    var outputSize: Int
}

private enum BenchmarkError: LocalizedError {
    case noDisplays
    case noMatchingDisplay
    case noImageBuffer
    case unsupportedPixelFormat(OSType)

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            return "ScreenCaptureKit did not report any displays."
        case .noMatchingDisplay:
            return "Could not match the current pointer screen to a ScreenCaptureKit display."
        case .noImageBuffer:
            return "A ScreenCaptureKit sample did not contain an image buffer."
        case .unsupportedPixelFormat(let pixelFormat):
            return "Unsupported pixel format \(pixelFormat); expected 32BGRA."
        }
    }
}

private final class ScreenCaptureBenchmarkOutput: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var frameCount = 0
    private var totalProcessingTime = 0.0
    private var maxProcessingTime = 0.0
    private var firstFrameTime: Double?
    private var lastFrameTime: Double?
    private var latestFeatures = ScreenSampleFeatures(
        sampleCount: 0,
        meanBrightness: 0,
        meanSaturation: 0,
        meanHue: 0,
        contrast: 0,
        warmth: 0
    )
    private var error: Error?

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else {
            return
        }

        let startedAt = ProcessInfo.processInfo.systemUptime

        do {
            let features = try features(from: sampleBuffer)
            let endedAt = ProcessInfo.processInfo.systemUptime
            record(features: features, processingTime: endedAt - startedAt, timestamp: endedAt)
        } catch BenchmarkError.noImageBuffer {
            return
        } catch {
            record(error: error)
        }
    }

    func snapshot() -> BenchmarkSnapshot {
        lock.withLock {
            BenchmarkSnapshot(
                frameCount: frameCount,
                totalProcessingTime: totalProcessingTime,
                maxProcessingTime: maxProcessingTime,
                elapsedFrameTime: (lastFrameTime ?? 0) - (firstFrameTime ?? 0),
                latestFeatures: latestFeatures,
                error: error
            )
        }
    }
}

private struct BenchmarkSnapshot {
    var frameCount: Int
    var totalProcessingTime: Double
    var maxProcessingTime: Double
    var elapsedFrameTime: Double
    var latestFeatures: ScreenSampleFeatures
    var error: Error?
}

private extension ScreenCaptureBenchmarkOutput {
    func features(from sampleBuffer: CMSampleBuffer) throws -> ScreenSampleFeatures {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw BenchmarkError.noImageBuffer
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            throw BenchmarkError.unsupportedPixelFormat(pixelFormat)
        }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
            throw BenchmarkError.noImageBuffer
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var accumulator = ScreenSampleFeatureAccumulator()

        for y in 0..<height {
            let row = bytes + y * bytesPerRow
            for x in 0..<width {
                let pixel = row + x * 4
                accumulator.add(
                    red: Double(pixel[2]) / 255,
                    green: Double(pixel[1]) / 255,
                    blue: Double(pixel[0]) / 255
                )
            }
        }

        return accumulator.finish()
    }

    func record(features: ScreenSampleFeatures, processingTime: Double, timestamp: Double) {
        lock.withLock {
            if firstFrameTime == nil {
                firstFrameTime = timestamp
            }
            lastFrameTime = timestamp
            frameCount += 1
            totalProcessingTime += processingTime
            maxProcessingTime = max(maxProcessingTime, processingTime)
            latestFeatures = features
        }
    }

    func record(error: Error) {
        lock.withLock {
            if self.error == nil {
                self.error = error
            }
        }
    }
}

private extension ScreenSamplerBenchmarkRunner {
    func runSyntheticReducerBenchmark(duration: TimeInterval) {
        let sampleSide = 24
        let pixelsPerSample = sampleSide * sampleSide
        let targetSamples = max(1, Int(duration * 30))
        let startedAt = ProcessInfo.processInfo.systemUptime

        var latestFeatures = ScreenSampleFeatures(
            sampleCount: 0,
            meanBrightness: 0,
            meanSaturation: 0,
            meanHue: 0,
            contrast: 0,
            warmth: 0
        )

        for sampleIndex in 0..<targetSamples {
            var accumulator = ScreenSampleFeatureAccumulator()
            for pixelIndex in 0..<pixelsPerSample {
                let phase = Double((sampleIndex * 31 + pixelIndex * 17) % 255) / 255
                accumulator.add(red: phase, green: 1 - phase, blue: Double(pixelIndex % 127) / 126)
            }
            latestFeatures = accumulator.finish()
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let averageMilliseconds = (elapsed / Double(targetSamples)) * 1_000
        print(
            String(
                format: "synthetic-reducer: samples=%d pixels/sample=%d avg_reduce_ms=%.4f last_brightness=%.3f last_contrast=%.3f",
                targetSamples,
                pixelsPerSample,
                averageMilliseconds,
                latestFeatures.meanBrightness,
                latestFeatures.contrast
            )
        )
    }

    func runScreenCaptureKitBenchmarks(duration: TimeInterval) async throws {
        let configurations = [
            BenchmarkConfiguration(name: "micro-crop-6hz", framesPerSecond: 6, cropSize: 96, outputSize: 24),
            BenchmarkConfiguration(name: "micro-crop-12hz", framesPerSecond: 12, cropSize: 96, outputSize: 24),
            BenchmarkConfiguration(name: "micro-crop-30hz", framesPerSecond: 30, cropSize: 96, outputSize: 24),
        ]

        for configuration in configurations {
            try await runScreenCaptureKitBenchmark(configuration: configuration, duration: duration)
        }
    }

    func runScreenCaptureKitBenchmark(
        configuration: BenchmarkConfiguration,
        duration: TimeInterval
    ) async throws {
        let content = try await SCShareableContent.current
        guard !content.displays.isEmpty else {
            throw BenchmarkError.noDisplays
        }

        let pointerLocation = NSEvent.mouseLocation
        let screen = screen(containing: pointerLocation)
        guard
            let displayID = displayID(for: screen),
            let display = content.displays.first(where: { $0.displayID == displayID })
        else {
            throw BenchmarkError.noMatchingDisplay
        }

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.sourceRect = sourceRect(
            centeredAt: pointerLocation,
            size: configuration.cropSize,
            displayFrame: display.frame
        )
        streamConfiguration.width = configuration.outputSize
        streamConfiguration.height = configuration.outputSize
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.framesPerSecond))
        streamConfiguration.queueDepth = 1
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.showsCursor = false
        streamConfiguration.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let output = ScreenCaptureBenchmarkOutput()
        let queue = DispatchQueue(label: "sounda.screen-sampler-benchmark")
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: nil)

        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()

        let updateCount = max(1, Int(duration * Double(configuration.framesPerSecond)))
        for updateIndex in 0..<updateCount {
            streamConfiguration.sourceRect = sourceRect(
                centeredAt: animatedPoint(
                    around: pointerLocation,
                    index: updateIndex,
                    count: updateCount,
                    displayFrame: display.frame
                ),
                size: configuration.cropSize,
                displayFrame: display.frame
            )
            try await stream.updateConfiguration(streamConfiguration)
            try await Task.sleep(nanoseconds: UInt64((1.0 / Double(configuration.framesPerSecond)) * 1_000_000_000))
        }

        try await stream.stopCapture()

        let snapshot = output.snapshot()
        if let error = snapshot.error {
            throw error
        }

        let averageReduceMilliseconds = snapshot.frameCount == 0
            ? 0
            : (snapshot.totalProcessingTime / Double(snapshot.frameCount)) * 1_000
        let maxReduceMilliseconds = snapshot.maxProcessingTime * 1_000
        let observedFramesPerSecond = snapshot.elapsedFrameTime > 0
            ? Double(snapshot.frameCount) / snapshot.elapsedFrameTime
            : 0

        print(
            String(
                format: "%@: target_hz=%d frames=%d observed_hz=%.2f avg_reduce_ms=%.4f max_reduce_ms=%.4f brightness=%.3f saturation=%.3f contrast=%.3f warmth=%.3f",
                configuration.name,
                configuration.framesPerSecond,
                snapshot.frameCount,
                observedFramesPerSecond,
                averageReduceMilliseconds,
                maxReduceMilliseconds,
                snapshot.latestFeatures.meanBrightness,
                snapshot.latestFeatures.meanSaturation,
                snapshot.latestFeatures.contrast,
                snapshot.latestFeatures.warmth
            )
        )
    }

    func sourceRect(centeredAt point: CGPoint, size: CGFloat, displayFrame: CGRect) -> CGRect {
        CGRect(
            x: min(max(point.x - size / 2, displayFrame.minX), displayFrame.maxX - size),
            y: min(max(displayFrame.maxY - point.y - size / 2, displayFrame.minY), displayFrame.maxY - size),
            width: min(size, displayFrame.width),
            height: min(size, displayFrame.height)
        )
    }

    func animatedPoint(
        around point: CGPoint,
        index: Int,
        count: Int,
        displayFrame: CGRect
    ) -> CGPoint {
        let radius = min(CGFloat(48), max(CGFloat(12), min(displayFrame.width, displayFrame.height) * 0.03))
        let angle = (Double(index) / Double(max(count, 1))) * .pi * 2

        return CGPoint(
            x: min(max(point.x + cos(angle) * radius, displayFrame.minX), displayFrame.maxX),
            y: min(max(point.y + sin(angle) * radius, displayFrame.minY), displayFrame.maxY)
        )
    }

    func screen(containing location: NSPoint) -> NSScreen {
        NSScreen.screens.first { screen in
            screen.frame.contains(location)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(screenNumber.uint32Value)
        }

        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private func runAsync(_ operation: @escaping () async throws -> Void) -> Result<Void, Error> {
    let semaphore = DispatchSemaphore(value: 0)
    final class Box: @unchecked Sendable {
        var result: Result<Void, Error>?
    }
    let box = Box()

    Task {
        do {
            try await operation()
            box.result = .success(())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()
    return box.result ?? .failure(BenchmarkError.noDisplays)
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer {
            unlock()
        }
        return try body()
    }
}
