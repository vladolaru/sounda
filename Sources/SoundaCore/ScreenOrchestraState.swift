public struct ScreenOrchestraState: Equatable, Sendable {
    public var isActive: Bool
    public var rootFrequency: Double
    public var amplitude: Double
    public var voiceCount: Int
    public var intervalSemitones: [Int]
    public var richness: Double
    public var motion: Double
    public var detuneCents: Double
    public var groove: ScreenGrooveState

    public init(
        isActive: Bool,
        rootFrequency: Double,
        amplitude: Double,
        voiceCount: Int,
        intervalSemitones: [Int],
        richness: Double,
        motion: Double,
        detuneCents: Double,
        groove: ScreenGrooveState = .silence
    ) {
        self.isActive = isActive
        self.rootFrequency = rootFrequency
        self.amplitude = amplitude
        self.voiceCount = voiceCount
        self.intervalSemitones = intervalSemitones
        self.richness = richness
        self.motion = motion
        self.detuneCents = detuneCents
        self.groove = groove
    }
}

public extension ScreenOrchestraState {
    static let silence = ScreenOrchestraState(
        isActive: false,
        rootFrequency: 0,
        amplitude: 0,
        voiceCount: 0,
        intervalSemitones: [],
        richness: 0,
        motion: 0,
        detuneCents: 0,
        groove: .silence
    )
}

public struct ScreenGrooveState: Equatable, Sendable {
    public var isActive: Bool
    public var kickIntensity: Double
    public var snareIntensity: Double
    public var hatIntensity: Double
    public var clapTriggered: Bool
    public var tempoBPM: Double

    public init(
        isActive: Bool,
        kickIntensity: Double,
        snareIntensity: Double,
        hatIntensity: Double,
        clapTriggered: Bool,
        tempoBPM: Double
    ) {
        self.isActive = isActive
        self.kickIntensity = kickIntensity
        self.snareIntensity = snareIntensity
        self.hatIntensity = hatIntensity
        self.clapTriggered = clapTriggered
        self.tempoBPM = tempoBPM
    }
}

public extension ScreenGrooveState {
    static let silence = ScreenGrooveState(
        isActive: false,
        kickIntensity: 0,
        snareIntensity: 0,
        hatIntensity: 0,
        clapTriggered: false,
        tempoBPM: 108
    )
}
