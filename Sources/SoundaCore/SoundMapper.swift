public struct SoundMapper: Sendable {
    public var settings: SoundaSettings

    public init(settings: SoundaSettings = .default) {
        self.settings = settings
    }

    public func map(_ frame: CursorFrame) -> SoundState {
        .silence
    }
}
