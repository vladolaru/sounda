import AppKit
import SoundaCore

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let contentViewController: SoundaControlsViewController

    init(
        settings: SoundaSettings,
        onSettingsChange: @escaping (SoundaSettings) -> Void,
        onQuit: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        contentViewController = SoundaControlsViewController(
            settings: settings,
            onSettingsChange: onSettingsChange,
            onQuit: onQuit
        )
        _ = contentViewController.view

        popover.behavior = .transient
        popover.contentSize = contentViewController.preferredContentSize
        popover.contentViewController = contentViewController

        if let button = statusItem.button {
            if let image = NSImage(
                systemSymbolName: "waveform.path.ecg",
                accessibilityDescription: "Sounda"
            ) {
                button.image = image
            } else {
                button.title = "Snd"
            }

            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    func updateReadout(_ soundState: SoundState) {
        DispatchQueue.main.async { [weak self] in
            self?.contentViewController.updateReadout(soundState)
        }
    }

    func updateAudioStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.contentViewController.updateAudioStatus(status)
        }
    }

    func updateScreenStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.contentViewController.updateScreenStatus(status)
        }
    }
}

private extension MenuBarController {
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private final class SoundaControlsViewController: NSViewController {
    private var settings: SoundaSettings
    private let onSettingsChange: (SoundaSettings) -> Void
    private let onQuit: () -> Void

    private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let volumeSlider = NSSlider(value: 0, minValue: 0, maxValue: 0.85, target: nil, action: nil)
    private let sensitivitySlider = NSSlider(value: 0, minValue: 0.08, maxValue: 0.70, target: nil, action: nil)
    private let accentSlider = NSSlider(value: 0, minValue: 0, maxValue: 0.95, target: nil, action: nil)
    private let presetPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let screenOrchestraButton = NSButton(checkboxWithTitle: "Screen chords", target: nil, action: nil)
    private let intensityValueLabel = NSTextField(labelWithString: "0%")
    private let noteValueLabel = NSTextField(labelWithString: "Silence")
    private let grooveValueLabel = NSTextField(labelWithString: "Drums quiet")
    private let audioStatusValueLabel = NSTextField(labelWithString: "Audio starting")
    private let screenStatusValueLabel = NSTextField(labelWithString: "Screen starting")

    init(
        settings: SoundaSettings,
        onSettingsChange: @escaping (SoundaSettings) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.settings = settings
        self.onSettingsChange = onSettingsChange
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildControls()
        syncControlsFromSettings()
    }

    func updateReadout(_ soundState: SoundState) {
        let intensity = Int((soundState.amplitude * 100).rounded())
        intensityValueLabel.stringValue = intensity > 0 ? "\(intensity)%" : "Quiet"
        noteValueLabel.stringValue = soundState.displayNoteName

        let groove = soundState.orchestra.groove
        let grooveEnergy = max(groove.kickIntensity, groove.snareIntensity, groove.hatIntensity)
        let groovePercent = Int((grooveEnergy * 100).rounded())
        grooveValueLabel.stringValue = groove.isActive ? "Drums \(groovePercent)%" : "Drums quiet"
    }

    func updateAudioStatus(_ status: String) {
        audioStatusValueLabel.stringValue = status
        audioStatusValueLabel.textColor = status.hasPrefix("Audio unavailable") ? .systemRed : .secondaryLabelColor
    }

    func updateScreenStatus(_ status: String) {
        screenStatusValueLabel.stringValue = status
        screenStatusValueLabel.toolTip = screenStatusTooltip(for: status)
        if status.hasPrefix("Screen unavailable") || status.hasPrefix("Screen permission") {
            screenStatusValueLabel.textColor = .systemOrange
        } else {
            screenStatusValueLabel.textColor = .secondaryLabelColor
        }
    }
}

private extension SoundaControlsViewController {
    func buildControls() {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        enabledButton.target = self
        enabledButton.action = #selector(enabledChanged(_:))
        stackView.addArrangedSubview(enabledButton)

        stackView.addArrangedSubview(sliderRow(title: "Master volume", slider: volumeSlider, action: #selector(volumeChanged(_:))))
        stackView.addArrangedSubview(sliderRow(title: "Sensitivity", slider: sensitivitySlider, action: #selector(sensitivityChanged(_:))))
        stackView.addArrangedSubview(sliderRow(title: "Accent amount", slider: accentSlider, action: #selector(accentChanged(_:))))
        stackView.addArrangedSubview(presetRow())
        screenOrchestraButton.target = self
        screenOrchestraButton.action = #selector(screenOrchestraChanged(_:))
        stackView.addArrangedSubview(screenOrchestraButton)
        stackView.addArrangedSubview(readoutRow(title: "Intensity", valueLabel: intensityValueLabel))
        stackView.addArrangedSubview(readoutRow(title: "Note", valueLabel: noteValueLabel))
        stackView.addArrangedSubview(readoutRow(title: "Groove", valueLabel: grooveValueLabel))
        stackView.addArrangedSubview(readoutRow(title: "Audio", valueLabel: audioStatusValueLabel))
        stackView.addArrangedSubview(readoutRow(title: "Screen", valueLabel: screenStatusValueLabel))

        let escapeLabel = NSTextField(labelWithString: "Escape: Control-Option-Command-Q")
        escapeLabel.font = .systemFont(ofSize: 11)
        escapeLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(escapeLabel)

        let quitButton = NSButton(title: "Quit Sounda", target: self, action: #selector(quit(_:)))
        quitButton.bezelStyle = .rounded
        stackView.addArrangedSubview(quitButton)

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
        ])

        resizeToFit(stackView: stackView)
    }

    func sliderRow(title: String, slider: NSSlider, action: Selector) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        slider.target = self
        slider.action = action
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let row = NSStackView(views: [titleLabel, slider])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 248).isActive = true

        return row
    }

    func presetRow() -> NSView {
        let titleLabel = NSTextField(labelWithString: "Preset")
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        for preset in SoundaSettings.Preset.allCases {
            presetPopUp.addItem(withTitle: preset.displayName)
        }
        presetPopUp.target = self
        presetPopUp.action = #selector(presetChanged(_:))
        presetPopUp.controlSize = .small

        let row = NSStackView(views: [titleLabel, presetPopUp])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 248).isActive = true

        return row
    }

    func readoutRow(title: String, valueLabel: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 248).isActive = true

        return row
    }

    func syncControlsFromSettings() {
        enabledButton.state = settings.isEnabled ? .on : .off
        volumeSlider.doubleValue = settings.masterVolume
        sensitivitySlider.doubleValue = settings.sensitivity
        accentSlider.doubleValue = settings.accentAmount
        screenOrchestraButton.state = settings.screenOrchestraEnabled ? .on : .off
        let presetIndex = SoundaSettings.Preset.allCases.firstIndex(of: settings.preset) ?? 0
        presetPopUp.selectItem(at: presetIndex)
    }

    func publishSettings() {
        onSettingsChange(settings)
    }

    @objc func enabledChanged(_ sender: NSButton) {
        settings.isEnabled = sender.state == .on
        publishSettings()
    }

    @objc func volumeChanged(_ sender: NSSlider) {
        settings.masterVolume = sender.doubleValue
        publishSettings()
    }

    @objc func sensitivityChanged(_ sender: NSSlider) {
        settings.sensitivity = sender.doubleValue
        publishSettings()
    }

    @objc func accentChanged(_ sender: NSSlider) {
        settings.accentAmount = sender.doubleValue
        publishSettings()
    }

    @objc func presetChanged(_ sender: NSPopUpButton) {
        let presets = SoundaSettings.Preset.allCases
        settings.preset = presets[clamp(sender.indexOfSelectedItem, lower: 0, upper: presets.count - 1)]
        publishSettings()
    }

    @objc func screenOrchestraChanged(_ sender: NSButton) {
        settings.screenOrchestraEnabled = sender.state == .on
        publishSettings()
    }

    @objc func quit(_ sender: NSButton) {
        onQuit()
    }

    func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    func resizeToFit(stackView: NSStackView) {
        view.layoutSubtreeIfNeeded()
        let contentHeight = ceil(stackView.fittingSize.height) + 32
        let size = NSSize(width: 280, height: max(300, contentHeight))
        preferredContentSize = size
        view.setFrameSize(size)
    }

    func screenStatusTooltip(for status: String) -> String {
        if status.hasPrefix("live") {
            return "Live screen samples: counter, brightness, saturation, contrast."
        }

        if status == "Screen permission requested" {
            return "macOS should ask for Screen Recording permission for this Sounda process."
        }

        if status == "Screen permission pending" || status == "Screen permission denied" {
            return "Grant Screen Recording permission for SoundaApp, then toggle Screen chords off and on."
        }

        return status
    }
}
