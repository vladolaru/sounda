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
            !lead.isSilent
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

        let hasScreenFeatures = features.map { $0.sampleCount > 0 } ?? false
        let targetFeatures = features.map(SmoothedScreenFeatures.init) ?? .neutralGroove
        let currentFeatures: SmoothedScreenFeatures
        if hasScreenFeatures, let smoothedFeatures {
            currentFeatures = smoothedFeatures.smoothed(toward: targetFeatures)
        } else {
            currentFeatures = targetFeatures
        }
        smoothedFeatures = hasScreenFeatures ? currentFeatures : nil

        let voiceCount = clampedVoiceCount(brightness: currentFeatures.brightness, saturation: currentFeatures.saturation)
        let richness = clamp(0.14 + currentFeatures.saturation * 0.34, lower: 0, upper: 0.48)
        let motion = clamp(currentFeatures.contrast * 0.10, lower: 0, upper: 0.12)
        let detuneCents = 0.4 + currentFeatures.saturation * 2.2
        let levelRatio = min(
            0.24,
            0.07 + currentFeatures.brightness * 0.12 + currentFeatures.saturation * 0.03
        )
        let amplitude = clamp(leadAmplitude * levelRatio, lower: 0, upper: leadAmplitude * 0.35)
        let groove = grooveState(lead: lead, features: currentFeatures, leadAmplitude: leadAmplitude)

        guard hasScreenFeatures, amplitude > orchestraSilenceThreshold, voiceCount > 0 else {
            return groove.isActive ? ScreenOrchestraState(
                isActive: false,
                rootFrequency: rootFrequency,
                amplitude: 0,
                voiceCount: 0,
                intervalSemitones: [],
                richness: 0,
                motion: 0,
                detuneCents: 0,
                groove: groove
            ) : .silence
        }

        return ScreenOrchestraState(
            isActive: true,
            rootFrequency: rootFrequency,
            amplitude: amplitude,
            voiceCount: voiceCount,
            intervalSemitones: intervals(hue: currentFeatures.hue, warmth: currentFeatures.warmth),
            richness: richness,
            motion: motion,
            detuneCents: detuneCents,
            groove: groove
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

    static let neutralGroove = SmoothedScreenFeatures(
        brightness: 0.45,
        saturation: 0.20,
        hue: 0.2,
        contrast: 0.45,
        warmth: 0
    )
}

private let screenFeatureSmoothing = 0.22
private let orchestraSilenceThreshold = 0.0005

private func clampedVoiceCount(brightness: Double, saturation: Double) -> Int {
    if brightness < 0.18 {
        return 1
    }

    if brightness > 0.72, saturation > 0.38 {
        return 3
    }

    return 2
}

private func intervals(hue: Double, warmth: Double) -> [Int] {
    if warmth >= 0.25 {
        return [0, 7, 12]
    }

    if warmth <= -0.25 {
        return hue >= 0.48 && hue <= 0.78 ? [0, 5, 12] : [0, 7, 14]
    }

    switch hue {
    case 0..<0.16, 0.88...1:
        return [0, 7, 12]
    case 0.25..<0.46:
        return [0, 5, 12]
    case 0.50..<0.78:
        return [0, 7, 14]
    default:
        return [0, 7, 12]
    }
}

private func grooveState(
    lead: SoundState,
    features: SmoothedScreenFeatures,
    leadAmplitude: Double
) -> ScreenGrooveState {
    let movementEnergy = clamp(leadAmplitude * 3.1, lower: 0, upper: 1)
    let tempoBPM = clamp(96 + features.contrast * 34 + features.saturation * 12, lower: 90, upper: 150)
    let kickIntensity = clamp((movementEnergy - 0.12) * (0.36 + features.brightness * 0.64), lower: 0, upper: 1)
    let hatIntensity = clamp(movementEnergy * (0.20 + features.contrast * 0.68), lower: 0, upper: 1)
    let snareIntensity = lead.accentTriggered
        ? clamp(0.30 + sanitizedUnit(lead.accentIntensity) * 0.72 + features.contrast * 0.16, lower: 0, upper: 1)
        : 0
    let isActive = kickIntensity > 0.02 || hatIntensity > 0.02 || snareIntensity > 0.02

    return ScreenGrooveState(
        isActive: isActive,
        kickIntensity: kickIntensity,
        snareIntensity: snareIntensity,
        hatIntensity: hatIntensity,
        clapTriggered: snareIntensity > 0.15,
        tempoBPM: tempoBPM
    )
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
