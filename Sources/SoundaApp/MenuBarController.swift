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

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 300)
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
    private let volumeSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let sensitivitySlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let accentSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let presetPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let intensityValueLabel = NSTextField(labelWithString: "0%")
    private let noteValueLabel = NSTextField(labelWithString: "Silence")

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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 300))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildControls()
        syncControlsFromSettings()
    }

    func updateReadout(_ soundState: SoundState) {
        let intensity = Int((soundState.amplitude * 100).rounded())
        intensityValueLabel.stringValue = "\(intensity)%"
        noteValueLabel.stringValue = soundState.displayNoteName
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
        stackView.addArrangedSubview(readoutRow(title: "Intensity", valueLabel: intensityValueLabel))
        stackView.addArrangedSubview(readoutRow(title: "Note", valueLabel: noteValueLabel))

        let colorMode = NSButton(checkboxWithTitle: "Color mode (experimental)", target: nil, action: nil)
        colorMode.state = .off
        colorMode.isEnabled = false
        stackView.addArrangedSubview(colorMode)

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

        presetPopUp.addItem(withTitle: "Minor pentatonic")
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
        presetPopUp.selectItem(at: 0)
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
        settings.preset = .minorPentatonic
        publishSettings()
    }

    @objc func quit(_ sender: NSButton) {
        onQuit()
    }
}
