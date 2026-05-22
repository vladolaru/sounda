public struct CursorFrame: Equatable, Sendable {
    public var timestamp: Double
    public var normalizedX: Double
    public var normalizedY: Double
    public var speed: Double
    public var acceleration: Double
    public var directionAngle: Double

    public init(
        timestamp: Double,
        normalizedX: Double,
        normalizedY: Double,
        speed: Double,
        acceleration: Double,
        directionAngle: Double
    ) {
        self.timestamp = timestamp
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.speed = speed
        self.acceleration = acceleration
        self.directionAngle = directionAngle
    }
}
