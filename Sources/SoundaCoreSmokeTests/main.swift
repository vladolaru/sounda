import Foundation
import SoundaCore

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("SoundaCore smoke test failed: \(message)\n".utf8))
        exit(1)
    }
}

func assertApproxEqual(_ actual: Double, _ expected: Double, accuracy: Double, _ message: String) {
    assert(abs(actual - expected) <= accuracy, "\(message): expected \(expected), got \(actual)")
}

func frame(
    timestamp: Double = 0,
    normalizedX: Double = 0.5,
    normalizedY: Double = 0.5,
    speed: Double = 0,
    acceleration: Double = 0,
    directionAngle: Double = 0
) -> CursorFrame {
    CursorFrame(
        timestamp: timestamp,
        normalizedX: normalizedX,
        normalizedY: normalizedY,
        speed: speed,
        acceleration: acceleration,
        directionAngle: directionAngle
    )
}

var mapper = SoundMapper(settings: SoundaSettings(sensitivity: 0.4))
let slow = mapper.map(frame(speed: 0.1))
assert(slow.isSilent, "slow movement below sensitivity should be silent")
assertApproxEqual(slow.amplitude, 0, accuracy: 0.0001, "silent amplitude")

mapper = SoundMapper(settings: .default)
let fast = mapper.map(frame(speed: 1.0))
assert(!fast.isSilent, "fast movement should not be silent")
assert(fast.amplitude > 0, "fast movement should produce non-zero amplitude")

mapper = SoundMapper(settings: .default)
let ordinary = mapper.map(frame(speed: 0.18))
assert(ordinary.isSilent, "ordinary pointer movement should remain silent by default")
assertApproxEqual(ordinary.amplitude, 0, accuracy: 0.0001, "ordinary movement amplitude")

mapper = SoundMapper(settings: .default)
let moderatelyFast = mapper.map(frame(speed: 0.55))
assert(!moderatelyFast.isSilent, "moderately fast movement should be audible by default")
assert(moderatelyFast.amplitude > 0.05, "moderately fast movement should become audible quickly")
assert(moderatelyFast.amplitude < 0.30, "moderately fast movement should not be startling")

mapper = SoundMapper(settings: .default)
let lowNote = mapper.map(frame(normalizedX: 0, speed: 1.0))
let highNote = mapper.map(frame(timestamp: 0.1, normalizedX: 1, speed: 1.0))
assert(lowNote.displayNoteName == "C4", "left edge should map to C4, got \(lowNote.displayNoteName)")
assert(highNote.displayNoteName == "C6", "right edge should map to C6, got \(highNote.displayNoteName)")
assertApproxEqual(lowNote.frequency, 261.625565, accuracy: 0.001, "C4 frequency")
assertApproxEqual(highNote.frequency, 1046.502261, accuracy: 0.001, "C6 frequency")

var lowMapper = SoundMapper(settings: .default)
var highMapper = SoundMapper(settings: .default)
let dim = lowMapper.map(frame(normalizedY: 0.1, speed: 1.0))
let bright = highMapper.map(frame(normalizedY: 0.9, speed: 1.0))
assert(bright.filterBrightness > dim.filterBrightness, "vertical position should increase filter brightness")

mapper = SoundMapper(settings: .default)
_ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
let accent = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))
assert(accent.accentTriggered, "sharp direction change should trigger accent")
assert(accent.accentIntensity > 0, "accent should have intensity")

let cooledDown = mapper.map(frame(timestamp: 0.4, speed: 1.0, directionAngle: 0))
assert(!cooledDown.accentTriggered, "accent cooldown should prevent rapid repeated accents")
assertApproxEqual(cooledDown.accentIntensity, 0, accuracy: 0.0001, "cooled down accent intensity")

mapper = SoundMapper(settings: .default)
_ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
let firstPlayableAccent = mapper.map(frame(timestamp: 0.2, speed: 1.0, directionAngle: .pi))
let blockedStutter = mapper.map(frame(timestamp: 0.32, speed: 1.0, directionAngle: 0))
let secondPlayableAccent = mapper.map(frame(timestamp: 0.40, speed: 1.0, directionAngle: .pi))
assert(firstPlayableAccent.accentTriggered, "accent should trigger after a short playable pause")
assert(!blockedStutter.accentTriggered, "accent cooldown should block stutter-speed repeats")
assert(secondPlayableAccent.accentTriggered, "accent cooldown should allow playful repeated sharp turns")

mapper = SoundMapper(settings: SoundaSettings(sensitivity: 0.2))
_ = mapper.map(frame(timestamp: 0, speed: 0.2, directionAngle: 0))
let thresholdTurn = mapper.map(frame(timestamp: 0.3, speed: 0.2, directionAngle: .pi))
assert(!thresholdTurn.accentTriggered, "accent should not trigger at exact sensitivity threshold")
assertApproxEqual(thresholdTurn.accentIntensity, 0, accuracy: 0.0001, "threshold accent intensity")
assert(thresholdTurn.isSilent, "threshold movement should remain silent")

mapper = SoundMapper(settings: .default)
_ = mapper.map(frame(timestamp: 0, speed: 0, directionAngle: 0))
let firstMovement = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))
assert(!firstMovement.accentTriggered, "silent startup frame should not seed first movement accent")
assertApproxEqual(firstMovement.accentIntensity, 0, accuracy: 0.0001, "first movement accent intensity")

mapper = SoundMapper(settings: .default)
_ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
_ = mapper.map(frame(timestamp: 0.1, speed: 0, directionAngle: 0))
let resumedMovement = mapper.map(frame(timestamp: 0.4, speed: 1.0, directionAngle: .pi))
assert(!resumedMovement.accentTriggered, "stopped frame should clear direction before movement resumes")
assertApproxEqual(resumedMovement.accentIntensity, 0, accuracy: 0.0001, "resumed movement accent intensity")

mapper = SoundMapper(settings: SoundaSettings(accentAmount: 0))
_ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
let zeroAccentAmount = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))
assert(!zeroAccentAmount.accentTriggered, "zero accent amount should not trigger accent event")
assertApproxEqual(zeroAccentAmount.accentIntensity, 0, accuracy: 0.0001, "zero accent amount intensity")

mapper = SoundMapper(settings: SoundaSettings(masterVolume: 0))
_ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
let zeroMasterVolume = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))
assert(!zeroMasterVolume.accentTriggered, "zero master volume should not trigger accent event")
assertApproxEqual(zeroMasterVolume.accentIntensity, 0, accuracy: 0.0001, "zero master volume intensity")

mapper = SoundMapper(settings: .default)
let moving = mapper.map(frame(timestamp: 0, speed: 1.0))
let stopped = mapper.map(frame(timestamp: 0.1, speed: 0))
assert(moving.amplitude > 0, "moving frame should have amplitude")
assert(stopped.amplitude > 0, "stopped frame should fade instead of hard cutting")
assert(stopped.amplitude < moving.amplitude, "stopped frame should fade toward silence")
assert(!stopped.isSilent, "stopped frame should not be marked silent while amplitude is audible")

var released = stopped
for index in 1...20 {
    released = mapper.map(frame(timestamp: 0.1 + Double(index) * 0.1, speed: 0))
}
assert(released.isSilent, "release fade should become silent after decaying below epsilon")
assertApproxEqual(released.amplitude, 0, accuracy: 0.001, "released amplitude")

mapper = SoundMapper(settings: .default)
let carriedFilter = mapper.map(frame(timestamp: 0, normalizedY: 1, speed: 1.0)).filterBrightness
mapper.settings = SoundaSettings(isEnabled: false)
let disabled = mapper.map(frame(timestamp: 0.1, normalizedY: 1, speed: 1.0, directionAngle: 0))
mapper.settings = .default
let afterDisabled = mapper.map(frame(timestamp: 0.2, normalizedY: 0, speed: 1.0, directionAngle: .pi))
var freshMapper = SoundMapper(settings: .default)
let fresh = freshMapper.map(frame(timestamp: 0.2, normalizedY: 0, speed: 1.0, directionAngle: .pi))
assert(carriedFilter > fresh.filterBrightness, "setup should create carried filter state")
assert(disabled.isSilent, "disabled state should be silent")
assertApproxEqual(disabled.filterBrightness, 0, accuracy: 0.0001, "disabled filter brightness")
assert(!afterDisabled.accentTriggered, "disabled state should clear previous direction")
assertApproxEqual(afterDisabled.filterBrightness, fresh.filterBrightness, accuracy: 0.0001, "filter brightness after disabled reset")

var minorMapper = SoundMapper(settings: SoundaSettings(preset: .minorPentatonic))
var ragtimeMapper = SoundMapper(settings: SoundaSettings(preset: .ragtime))
var glassMapper = SoundMapper(settings: SoundaSettings(preset: .glassChimes))
var bassMapper = SoundMapper(settings: SoundaSettings(preset: .warmBass))
var violinMapper = SoundMapper(settings: SoundaSettings(preset: .violinLead))
let minor = minorMapper.map(frame(normalizedX: 0.75, speed: 1.0))
let ragtime = ragtimeMapper.map(frame(normalizedX: 0.75, speed: 1.0))
let glass = glassMapper.map(frame(normalizedX: 0.75, speed: 1.0))
let bass = bassMapper.map(frame(normalizedX: 0.75, speed: 1.0))
let violin = violinMapper.map(frame(normalizedX: 0.75, speed: 1.0))
assert(minor.displayNoteName != ragtime.displayNoteName, "ragtime preset should pick distinct notes")
assert(minor.displayNoteName != glass.displayNoteName, "glass preset should pick distinct notes")
assert(minor.displayNoteName != bass.displayNoteName, "bass preset should pick distinct notes")
assert(minor.displayNoteName != violin.displayNoteName, "violin preset should pick distinct notes")
assert(ragtime.frequency < glass.frequency, "ragtime preset should sit below the glass preset")
assert(glass.frequency > minor.frequency, "glass preset should sit above the default preset")
assert(bass.frequency < minor.frequency, "bass preset should sit below the default preset")
assert(violin.frequency > minor.frequency, "violin preset should sit above the default preset")
assert(violin.frequency < glass.frequency, "violin preset should sit below the glass preset")
assert(violin.leadTimbre == .violin, "violin preset should use violin lead timbre")

mapper = SoundMapper(
    settings: SoundaSettings(
        masterVolume: .nan,
        sensitivity: .infinity,
        accentAmount: -.infinity
    )
)
let sanitized = mapper.map(
    frame(
        timestamp: .nan,
        normalizedX: .nan,
        normalizedY: .infinity,
        speed: .nan,
        acceleration: .nan,
        directionAngle: .nan
    )
)
assert(sanitized.frequency.isFinite, "frequency should be finite for non-finite input")
assert(sanitized.amplitude.isFinite, "amplitude should be finite for non-finite input")
assert(sanitized.filterBrightness.isFinite, "filter brightness should be finite for non-finite input")
assert(sanitized.accentIntensity.isFinite, "accent intensity should be finite for non-finite input")

var featureAccumulator = ScreenSampleFeatureAccumulator()
featureAccumulator.add(red: 1, green: 0, blue: 0)
featureAccumulator.add(red: 0, green: 0, blue: 1)
featureAccumulator.add(red: 1, green: 1, blue: 1)
let features = featureAccumulator.finish()
assert(features.sampleCount == 3, "screen sampler feature accumulator should count samples")
assertApproxEqual(features.meanBrightness, 5.0 / 9.0, accuracy: 0.0001, "screen sampler mean brightness")
assert(features.meanSaturation > 0.6, "screen sampler should report saturation")
assert(features.contrast > 0.6, "screen sampler should report contrast")
assertApproxEqual(features.warmth, 0, accuracy: 0.0001, "screen sampler warmth")

var orchestraMapper = ScreenOrchestraMapper()
let leadForOrchestra = SoundState(
    isSilent: false,
    frequency: 440,
    amplitude: 0.6,
    filterBrightness: 0.5,
    accentTriggered: false,
    accentIntensity: 0,
    displayNoteName: "A4"
)
let quietOrchestra = orchestraMapper.map(lead: leadForOrchestra, features: nil, isEnabled: true)
assert(!quietOrchestra.isActive, "missing screen features should keep screen chords silent")
assert(quietOrchestra.groove.isActive, "missing screen features should still allow cursor drums")

var dimOrchestraMapper = ScreenOrchestraMapper()
var brightOrchestraMapper = ScreenOrchestraMapper()
let dimOrchestra = dimOrchestraMapper.map(
    lead: leadForOrchestra,
    features: ScreenSampleFeatures(
        sampleCount: 576,
        meanBrightness: 0.12,
        meanSaturation: 0.25,
        meanHue: 0.2,
        contrast: 0.08,
        warmth: 0.1
    ),
    isEnabled: true
)
let brightOrchestra = brightOrchestraMapper.map(
    lead: leadForOrchestra,
    features: ScreenSampleFeatures(
        sampleCount: 576,
        meanBrightness: 0.86,
        meanSaturation: 0.25,
        meanHue: 0.2,
        contrast: 0.08,
        warmth: 0.1
    ),
    isEnabled: true
)
assert(dimOrchestra.isActive, "dim sampled screen should still create a quiet orchestra bed")
assert(brightOrchestra.voiceCount > dimOrchestra.voiceCount, "brighter screen should add orchestra density")
assert(brightOrchestra.amplitude > dimOrchestra.amplitude, "brighter screen should raise orchestra level")
assert(brightOrchestra.amplitude <= leadForOrchestra.amplitude * 0.35, "orchestra should stay below the lead")
assert(brightOrchestra.voiceCount <= 3, "screen orchestra should avoid too many chord voices by default")
assert(brightOrchestra.motion <= 0.12, "screen orchestra should not create warbly pad motion")
assert(brightOrchestra.detuneCents <= 3, "screen orchestra detune should stay subtle")

var grooveMapper = ScreenOrchestraMapper()
let grooveBand = grooveMapper.map(
    lead: leadForOrchestra,
    features: ScreenSampleFeatures(
        sampleCount: 576,
        meanBrightness: 0.55,
        meanSaturation: 0.35,
        meanHue: 0.2,
        contrast: 0.75,
        warmth: 0.1
    ),
    isEnabled: true
).groove
assert(grooveBand.isActive, "screen band should create groove energy while the cursor lead is moving")
assert(grooveBand.kickIntensity > 0.1, "screen band should drive kick energy from movement")
assert(grooveBand.hatIntensity > 0.2, "screen band should drive hi-hat energy from contrast and movement")
assert(grooveBand.tempoBPM >= 90 && grooveBand.tempoBPM <= 150, "screen band tempo should stay in a controlled range")

var noScreenGrooveMapper = ScreenOrchestraMapper()
let noScreenGrooveBand = noScreenGrooveMapper.map(
    lead: leadForOrchestra,
    features: nil,
    isEnabled: true
)
assert(!noScreenGrooveBand.isActive, "missing screen samples should not create screen chords")
assert(noScreenGrooveBand.groove.isActive, "missing screen samples should still allow cursor drums")
assert(noScreenGrooveBand.groove.kickIntensity > 0.1, "cursor drums should include kick energy without screen capture")
assert(noScreenGrooveBand.groove.hatIntensity > 0.1, "cursor drums should include hat energy without screen capture")

print("SoundaCore smoke test passed")
