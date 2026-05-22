public struct SoundState: Equatable, Sendable {
    public var isEnabled: Bool
    public var isSilent: Bool
    public var frequency: Double
    public var amplitude: Double
    public var filterBrightness: Double
    public var accentTriggered: Bool
    public var accentIntensity: Double
    public var displayNoteName: String

    public init(
        isEnabled: Bool = true,
        isSilent: Bool,
        frequency: Double,
        amplitude: Double,
        filterBrightness: Double,
        accentTriggered: Bool,
        accentIntensity: Double,
        displayNoteName: String
    ) {
        self.isEnabled = isEnabled
        self.isSilent = isSilent
        self.frequency = frequency
        self.amplitude = amplitude
        self.filterBrightness = filterBrightness
        self.accentTriggered = accentTriggered
        self.accentIntensity = accentIntensity
        self.displayNoteName = displayNoteName
    }
}

public extension SoundState {
    static let silence = SoundState(
        isEnabled: true,
        isSilent: true,
        frequency: 0,
        amplitude: 0,
        filterBrightness: 0,
        accentTriggered: false,
        accentIntensity: 0,
        displayNoteName: "Silence"
    )
}
