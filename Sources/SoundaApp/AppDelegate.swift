import AppKit
import Foundation
import SoundaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let debugSampleLimit: Int?
    private var printedSamples = 0

    private var settings: SoundaSettings {
        didSet {
            soundMapper.settings = settings
        }
    }

    private var menuBarController: MenuBarController?
    private var cursorTracker: CursorTracker?
    private var keyboardEscapeController: KeyboardEscapeController?
    private var audioEngineController: AudioEngineController?
    private var soundMapper: SoundMapper

    init(arguments: [String] = Array(CommandLine.arguments.dropFirst())) {
        self.debugSampleLimit = AppDelegate.cursorDebugSampleLimit(from: arguments)
        self.settings = .default
        self.soundMapper = SoundMapper(settings: .default)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        audioEngineController = AudioEngineController()

        let menuBarController = MenuBarController(
            settings: settings,
            onSettingsChange: { [weak self] settings in
                self?.handleSettingsChange(settings)
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
        self.menuBarController = menuBarController
        let keyboardEscapeController = KeyboardEscapeController {
            NSApplication.shared.terminate(nil)
        }
        self.keyboardEscapeController = keyboardEscapeController

        let tracker = CursorTracker { [weak self] frame in
            self?.handleCursorFrame(frame)
        }
        self.cursorTracker = tracker

        print("Sounda starting...")
        print("Escape hatch: press Control-Option-Command-Q, or Ctrl-C from this terminal.")
        keyboardEscapeController.start()
        updateAudioEngineForCurrentSettings()
        tracker.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioEngineController?.stop()
        keyboardEscapeController?.stop()
        cursorTracker?.stop()
    }
}

private extension AppDelegate {
    func handleSettingsChange(_ settings: SoundaSettings) {
        self.settings = settings
        updateAudioEngineForCurrentSettings()
    }

    func updateAudioEngineForCurrentSettings() {
        guard let audioEngineController else {
            return
        }

        if settings.isEnabled {
            let didStart = audioEngineController.start()
            menuBarController?.updateAudioStatus(
                didStart ? "Audio running" : (audioEngineController.errorMessage ?? "Audio unavailable")
            )
        } else {
            audioEngineController.stop()
            menuBarController?.updateAudioStatus("Audio off")
        }
    }

    func handleCursorFrame(_ frame: CursorFrame) {
        soundMapper.settings = settings
        let soundState = soundMapper.map(frame)
        audioEngineController?.updateState(soundState)
        menuBarController?.updateReadout(soundState)

        guard let debugSampleLimit else {
            return
        }

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

    static func cursorDebugSampleLimit(from arguments: [String]) -> Int? {
        guard
            let flagIndex = arguments.firstIndex(of: "--cursor-debug-samples"),
            arguments.indices.contains(arguments.index(after: flagIndex)),
            let limit = Int(arguments[arguments.index(after: flagIndex)])
        else {
            return nil
        }

        return max(0, limit)
    }
}
