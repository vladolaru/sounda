import Foundation

public struct ScreenOrchestraMapper: Sendable {
    private var smoothedFeatures: SmoothedScreenFeatures?

    public init() {}

    public mutating func map(
        lead: SoundState,
        features: ScreenSampleFeatures?,
        isEnabled: Bool = true
    ) -> ScreenOrchestraState {
        guard
            isEnabled,
            lead.isEnabled,
            !lead.isSilent,
            let features,
            features.sampleCount > 0
        else {
            smoothedFeatures = nil
            return .silence
        }

        let rootFrequency = sanitizedFrequency(lead.frequency)
        let leadAmplitude = sanitizedUnit(lead.amplitude)
        guard rootFrequency > 0, leadAmplitude > 0 else {
            smoothedFeatures = nil
            return .silence
        }

        let targetFeatures = SmoothedScreenFeatures(features)
        let currentFeatures: SmoothedScreenFeatures
        if let smoothedFeatures {
            currentFeatures = smoothedFeatures.smoothed(toward: targetFeatures)
        } else {
            currentFeatures = targetFeatures
        }
        smoothedFeatures = currentFeatures

        let voiceCount = clampedVoiceCount(for: currentFeatures.brightness)
        let richness = clamp(0.18 + currentFeatures.saturation * 0.82, lower: 0, upper: 1)
        let motion = clamp(pow(currentFeatures.contrast, 0.7), lower: 0, upper: 1)
        let detuneCents = 1.0 + currentFeatures.saturation * 9.0
        let levelRatio = min(
            0.35,
            0.10 + currentFeatures.brightness * 0.18 + currentFeatures.saturation * 0.05
        )
        let amplitude = clamp(leadAmplitude * levelRatio, lower: 0, upper: leadAmplitude * 0.35)

        guard amplitude > orchestraSilenceThreshold, voiceCount > 0 else {
            return .silence
        }

        return ScreenOrchestraState(
            isActive: true,
            rootFrequency: rootFrequency,
            amplitude: amplitude,
            voiceCount: voiceCount,
            intervalSemitones: intervals(hue: currentFeatures.hue, warmth: currentFeatures.warmth),
            richness: richness,
            motion: motion,
            detuneCents: detuneCents
        )
    }
}

private struct SmoothedScreenFeatures: Sendable {
    var brightness: Double
    var saturation: Double
    var hue: Double
    var contrast: Double
    var warmth: Double

    init(_ features: ScreenSampleFeatures) {
        brightness = sanitizedUnit(features.meanBrightness)
        saturation = sanitizedUnit(features.meanSaturation)
        hue = sanitizedUnit(features.meanHue)
        contrast = sanitizedUnit(features.contrast)
        warmth = clamp(sanitizedFinite(features.warmth, fallback: 0), lower: -1, upper: 1)
    }

    func smoothed(toward target: SmoothedScreenFeatures) -> SmoothedScreenFeatures {
        SmoothedScreenFeatures(
            brightness: smooth(current: brightness, target: target.brightness),
            saturation: smooth(current: saturation, target: target.saturation),
            hue: smoothHue(current: hue, target: target.hue),
            contrast: smooth(current: contrast, target: target.contrast),
            warmth: smooth(current: warmth, target: target.warmth)
        )
    }

    private init(
        brightness: Double,
        saturation: Double,
        hue: Double,
        contrast: Double,
        warmth: Double
    ) {
        self.brightness = brightness
        self.saturation = saturation
        self.hue = hue
        self.contrast = contrast
        self.warmth = warmth
    }
}

private let screenFeatureSmoothing = 0.22
private let orchestraSilenceThreshold = 0.0005

private func clampedVoiceCount(for brightness: Double) -> Int {
    clamp(Int((brightness * 3).rounded()) + 1, lower: 1, upper: 4)
}

private func intervals(hue: Double, warmth: Double) -> [Int] {
    if warmth >= 0.25 {
        return [0, 4, 7, 14]
    }

    if warmth <= -0.25 {
        return hue >= 0.48 && hue <= 0.78 ? [0, 5, 7, 12] : [0, 3, 7, 10]
    }

    switch hue {
    case 0..<0.16, 0.88...1:
        return [0, 4, 7, 12]
    case 0.25..<0.46:
        return [0, 5, 9, 14]
    case 0.50..<0.78:
        return [0, 7, 12, 19]
    default:
        return [0, 3, 7, 12]
    }
}

private func smooth(current: Double, target: Double) -> Double {
    current + (target - current) * screenFeatureSmoothing
}

private func smoothHue(current: Double, target: Double) -> Double {
    var delta = target - current
    if delta > 0.5 {
        delta -= 1
    } else if delta < -0.5 {
        delta += 1
    }

    let smoothed = current + delta * screenFeatureSmoothing
    let wrapped = smoothed.truncatingRemainder(dividingBy: 1)
    return wrapped >= 0 ? wrapped : wrapped + 1
}

private func sanitizedFrequency(_ frequency: Double) -> Double {
    guard frequency.isFinite, frequency > 0 else {
        return 0
    }

    return min(frequency, 4_000)
}

private func sanitizedUnit(_ value: Double) -> Double {
    clamp(sanitizedFinite(value, fallback: 0), lower: 0, upper: 1)
}

private func sanitizedFinite(_ value: Double, fallback: Double) -> Double {
    value.isFinite ? value : fallback
}

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}

private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
}
