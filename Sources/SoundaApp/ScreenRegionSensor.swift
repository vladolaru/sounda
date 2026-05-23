import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import SoundaCore

final class ScreenRegionSensor {
    private let onSample: (ScreenSampleFeatures) -> Void
    private let onStatusChange: (String) -> Void
    private let sampleQueue = DispatchQueue(label: "sounda.screen-region-sensor.samples")
    private var captureTask: Task<Void, Never>?
    private var stream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?
    private var streamOutput: ScreenRegionSensorOutput?
    private var activeDisplayID: CGDirectDisplayID?
    private var sampleStatusCounter = 0

    init(
        onSample: @escaping (ScreenSampleFeatures) -> Void,
        onStatusChange: @escaping (String) -> Void
    ) {
        self.onSample = onSample
        self.onStatusChange = onStatusChange
    }

    var isRunning: Bool {
        captureTask != nil
    }

    func start() {
        guard captureTask == nil else {
            return
        }

        if !CGPreflightScreenCaptureAccess() {
            publishStatus("Screen permission requested")
            guard CGRequestScreenCaptureAccess() else {
                publishStatus("Screen permission denied")
                return
            }
        }

        guard CGPreflightScreenCaptureAccess() else {
            publishStatus("Screen permission pending")
            return
        }

        captureTask = Task { [weak self] in
            await self?.runCaptureLoop()
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        Task { [weak self] in
            await self?.stopActiveStream()
        }
        publishStatus("Screen chords off")
    }
}

private extension ScreenRegionSensor {
    func runCaptureLoop() async {
        publishStatus("Screen chords starting")
        defer {
            captureTask = nil
        }

        while !Task.isCancelled {
            do {
                let content = try await SCShareableContent.current
                let pointerLocation = NSEvent.mouseLocation
                let screen = screen(containing: pointerLocation)
                guard
                    let displayID = displayID(for: screen),
                    let display = content.displays.first(where: { $0.displayID == displayID })
                else {
                    throw ScreenRegionSensorError.noMatchingDisplay
                }

                try await ensureStream(display: display, pointerLocation: pointerLocation)
                try await followPointer(on: display)
            } catch is CancellationError {
                break
            } catch {
                publishStatus("Screen unavailable: \(error.localizedDescription)")
                await stopActiveStream()
                break
            }
        }

        await stopActiveStream()
    }

    func ensureStream(display: SCDisplay, pointerLocation: CGPoint) async throws {
        if activeDisplayID == display.displayID, stream != nil {
            return
        }

        await stopActiveStream()

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect(
            centeredAt: pointerLocation,
            size: sensorCropSize,
            displayFrame: display.frame
        )
        configuration.width = sensorOutputSize
        configuration.height = sensorOutputSize
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(sensorFramesPerSecond))
        configuration.queueDepth = 1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let output = ScreenRegionSensorOutput { [weak self] features in
            self?.publishSample(features)
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        streamConfiguration = configuration
        streamOutput = output
        activeDisplayID = display.displayID
        publishStatus("Screen chords active")
    }

    func followPointer(on display: SCDisplay) async throws {
        guard let stream, let configuration = streamConfiguration else {
            return
        }

        while !Task.isCancelled {
            let pointerLocation = NSEvent.mouseLocation
            let currentScreen = screen(containing: pointerLocation)
            if displayID(for: currentScreen) != activeDisplayID {
                return
            }

            configuration.sourceRect = sourceRect(
                centeredAt: pointerLocation,
                size: sensorCropSize,
                displayFrame: display.frame
            )
            try await stream.updateConfiguration(configuration)
            try await Task.sleep(nanoseconds: sensorFrameIntervalNanoseconds)
        }
    }

    func stopActiveStream() async {
        if let stream {
            try? await stream.stopCapture()
        }

        stream = nil
        streamConfiguration = nil
        streamOutput = nil
        activeDisplayID = nil
        sampleStatusCounter = 0
    }

    func publishSample(_ features: ScreenSampleFeatures) {
        sampleStatusCounter += 1
        let status = sampleStatus(features, counter: sampleStatusCounter)
        DispatchQueue.main.async { [onSample, onStatusChange] in
            onSample(features)
            onStatusChange(status)
        }
    }

    func publishStatus(_ status: String) {
        DispatchQueue.main.async { [onStatusChange] in
            onStatusChange(status)
        }
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

    func sourceRect(centeredAt point: CGPoint, size: CGFloat, displayFrame: CGRect) -> CGRect {
        CGRect(
            x: min(max(point.x - size / 2, displayFrame.minX), displayFrame.maxX - size),
            y: min(max(displayFrame.maxY - point.y - size / 2, displayFrame.minY), displayFrame.maxY - size),
            width: min(size, displayFrame.width),
            height: min(size, displayFrame.height)
        )
    }

    func sampleStatus(_ features: ScreenSampleFeatures, counter: Int) -> String {
        String(
            format: "live #%d b%02d s%02d c%02d",
            counter % 1_000,
            percentage(features.meanBrightness),
            percentage(features.meanSaturation),
            percentage(features.contrast)
        )
    }

    func percentage(_ value: Double) -> Int {
        guard value.isFinite else {
            return 0
        }

        return min(max(Int((value * 100).rounded()), 0), 99)
    }
}

private final class ScreenRegionSensorOutput: NSObject, SCStreamOutput {
    private let onSample: (ScreenSampleFeatures) -> Void

    init(onSample: @escaping (ScreenSampleFeatures) -> Void) {
        self.onSample = onSample
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else {
            return
        }

        guard let features = try? self.features(from: sampleBuffer) else {
            return
        }

        onSample(features)
    }
}

private extension ScreenRegionSensorOutput {
    func features(from sampleBuffer: CMSampleBuffer) throws -> ScreenSampleFeatures {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw ScreenRegionSensorError.noImageBuffer
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            throw ScreenRegionSensorError.unsupportedPixelFormat(pixelFormat)
        }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
            throw ScreenRegionSensorError.noImageBuffer
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
}

private enum ScreenRegionSensorError: LocalizedError {
    case noMatchingDisplay
    case noImageBuffer
    case unsupportedPixelFormat(OSType)

    var errorDescription: String? {
        switch self {
        case .noMatchingDisplay:
            return "Could not match the current pointer screen to a capture display."
        case .noImageBuffer:
            return "A screen sample did not contain an image buffer."
        case .unsupportedPixelFormat(let pixelFormat):
            return "Unsupported pixel format \(pixelFormat); expected 32BGRA."
        }
    }
}

private let sensorFramesPerSecond = 6
private let sensorFrameIntervalNanoseconds = UInt64((1.0 / Double(sensorFramesPerSecond)) * 1_000_000_000)
private let sensorCropSize = CGFloat(96)
private let sensorOutputSize = 24
