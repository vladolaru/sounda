public struct SoundaSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var masterVolume: Double
    public var sensitivity: Double
    public var accentAmount: Double
    public var preset: Preset

    public init(
        isEnabled: Bool = true,
        masterVolume: Double = 0.42,
        sensitivity: Double = 0.32,
        accentAmount: Double = 0.68,
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
    enum Preset: String, CaseIterable, Equatable, Sendable {
        case minorPentatonic
        case glassChimes
        case warmBass

        public var displayName: String {
            switch self {
            case .minorPentatonic:
                return "Minor pentatonic"
            case .glassChimes:
                return "Glass chimes"
            case .warmBass:
                return "Warm bass"
            }
        }
    }

    static let `default` = SoundaSettings()
}
