import Foundation

public struct SoundMapper: Sendable {
    public var settings: SoundaSettings
    private var smoothedAmplitude: Double
    private var smoothedFilterBrightness: Double
    private var previousDirectionAngle: Double?
    private var lastAccentTime: Double?

    public init(settings: SoundaSettings = .default) {
        self.settings = settings
        self.smoothedAmplitude = 0
        self.smoothedFilterBrightness = 0
        self.previousDirectionAngle = nil
        self.lastAccentTime = nil
    }

    public mutating func map(_ frame: CursorFrame) -> SoundState {
        guard settings.isEnabled else {
            resetTransientState()

            return SoundState(
                isEnabled: false,
                isSilent: true,
                frequency: 0,
                amplitude: 0,
                filterBrightness: 0,
                accentTriggered: false,
                accentIntensity: 0,
                displayNoteName: "Disabled"
            )
        }

        let normalizedX = sanitizedClamp(frame.normalizedX, lower: 0, upper: 1, fallback: 0.5)
        let normalizedY = sanitizedClamp(frame.normalizedY, lower: 0, upper: 1, fallback: 0.5)
        let speed = sanitizedNonNegative(frame.speed)
        let timestamp = sanitizedFinite(frame.timestamp, fallback: 0)
        let sensitivity = sanitizedClamp(settings.sensitivity, lower: 0, upper: 1, fallback: SoundaSettings.default.sensitivity)
        let masterVolume = sanitizedClamp(settings.masterVolume, lower: 0, upper: 1, fallback: SoundaSettings.default.masterVolume)
        let accentAmount = sanitizedClamp(settings.accentAmount, lower: 0, upper: 1, fallback: SoundaSettings.default.accentAmount)
        let movementIntensity = normalizedMovementIntensity(speed: speed, sensitivity: sensitivity)
        let targetAmplitude = movementIntensity * masterVolume

        smoothedAmplitude = smooth(current: smoothedAmplitude, target: targetAmplitude)
        if smoothedAmplitude < silentAmplitudeEpsilon {
            smoothedAmplitude = 0
        }

        let targetFilterBrightness = clamp(0.15 + normalizedY * 0.75 + movementIntensity * 0.10, lower: 0, upper: 1)
        smoothedFilterBrightness = smooth(current: smoothedFilterBrightness, target: targetFilterBrightness)

        let note = noteForHorizontalPosition(normalizedX, preset: settings.preset)
        let angle = clampedAngle(frame.directionAngle)
        let accent = accentState(
            angle: angle,
            timestamp: timestamp,
            movementIntensity: movementIntensity,
            accentAmount: accentAmount,
            masterVolume: masterVolume
        )
        if movementIntensity > 0 {
            previousDirectionAngle = angle
        } else {
            previousDirectionAngle = nil
        }

        return SoundState(
            isEnabled: true,
            isSilent: smoothedAmplitude <= silentAmplitudeEpsilon,
            frequency: note.frequency,
            amplitude: smoothedAmplitude,
            filterBrightness: smoothedFilterBrightness,
            accentTriggered: accent.triggered,
            accentIntensity: accent.intensity,
            displayNoteName: note.name
        )
    }
}

private let minorPentatonicSemitones = [0, 3, 5, 7, 10, 12, 15, 17, 19, 22, 24]
private let baseFrequency = 261.6255653005986
private let attackSmoothing = 0.65
private let releaseSmoothing = 0.35
private let accentDirectionThreshold = Double.pi * 0.65
private let accentCooldown = 0.25
private let silentAmplitudeEpsilon = 0.001

private extension SoundMapper {
    mutating func resetTransientState() {
        smoothedAmplitude = 0
        smoothedFilterBrightness = 0
        previousDirectionAngle = nil
        lastAccentTime = nil
    }

    mutating func accentState(
        angle: Double,
        timestamp: Double,
        movementIntensity: Double,
        accentAmount: Double,
        masterVolume: Double
    ) -> (triggered: Bool, intensity: Double) {
        guard
            movementIntensity > 0,
            let previousDirectionAngle
        else {
            return (false, 0)
        }

        let directionChange = angularDistance(from: previousDirectionAngle, to: angle)
        let hasCooledDown = lastAccentTime.map { timestamp - $0 >= accentCooldown } ?? true
        guard directionChange >= accentDirectionThreshold, hasCooledDown else {
            return (false, 0)
        }

        let intensity = clamp((directionChange / Double.pi) * accentAmount * masterVolume, lower: 0, upper: 1)
        guard intensity > 0 else {
            return (false, 0)
        }

        lastAccentTime = timestamp
        return (true, intensity)
    }

    func noteForHorizontalPosition(
        _ normalizedX: Double,
        preset: SoundaSettings.Preset
    ) -> (name: String, frequency: Double) {
        switch preset {
        case .minorPentatonic:
            let index = Int((normalizedX * Double(minorPentatonicSemitones.count - 1)).rounded())
            let semitone = minorPentatonicSemitones[clamp(index, lower: 0, upper: minorPentatonicSemitones.count - 1)]
            let frequency = baseFrequency * pow(2, Double(semitone) / 12)
            return (noteName(forSemitone: semitone), frequency)
        }
    }

    func normalizedMovementIntensity(speed: Double, sensitivity: Double) -> Double {
        guard speed > sensitivity else {
            return 0
        }

        let usableRange = max(0.0001, 1 - sensitivity)
        return clamp((speed - sensitivity) / usableRange, lower: 0, upper: 1)
    }

    func smooth(current: Double, target: Double) -> Double {
        let coefficient = target > current ? attackSmoothing : releaseSmoothing
        return current + (target - current) * coefficient
    }
}

private func noteName(forSemitone semitone: Int) -> String {
    let names = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    let octave = 4 + semitone / 12
    return "\(names[semitone % 12])\(octave)"
}

private func clampedAngle(_ angle: Double) -> Double {
    guard angle.isFinite else {
        return 0
    }

    let twoPi = Double.pi * 2
    let remainder = angle.truncatingRemainder(dividingBy: twoPi)
    return remainder >= 0 ? remainder : remainder + twoPi
}

private func angularDistance(from firstAngle: Double, to secondAngle: Double) -> Double {
    let difference = abs(clampedAngle(secondAngle) - clampedAngle(firstAngle))
    return min(difference, Double.pi * 2 - difference)
}

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}

private func sanitizedClamp(_ value: Double, lower: Double, upper: Double, fallback: Double) -> Double {
    clamp(sanitizedFinite(value, fallback: fallback), lower: lower, upper: upper)
}

private func sanitizedFinite(_ value: Double, fallback: Double) -> Double {
    value.isFinite ? value : fallback
}

private func sanitizedNonNegative(_ value: Double) -> Double {
    max(0, sanitizedFinite(value, fallback: 0))
}

private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
}
