public struct SoundaSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var masterVolume: Double
    public var sensitivity: Double
    public var accentAmount: Double
    public var preset: Preset

    public init(
        isEnabled: Bool = true,
        masterVolume: Double = 0.6,
        sensitivity: Double = 0.2,
        accentAmount: Double = 0.5,
        preset: Preset = .minorPentatonic
    ) {
        self.isEnabled = isEnabled
        self.masterVolume = masterVolume
        self.sensitivity = sensitivity
        self.accentAmount = accentAmount
        self.preset = preset
    }
}

public extension SoundaSettings {
    enum Preset: String, Equatable, Sendable {
        case minorPentatonic
    }

    static let `default` = SoundaSettings()
}
