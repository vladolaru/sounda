@testable import SoundaCore

#if canImport(XCTest)
import XCTest

final class SoundMapperTests: XCTestCase {
    func testSlowMovementBelowSensitivityMapsToSilence() {
        var mapper = SoundMapper(settings: SoundaSettings(sensitivity: 0.4))

        let state = mapper.map(frame(speed: 0.1))

        XCTAssertTrue(state.isSilent)
        XCTAssertEqual(state.amplitude, 0, accuracy: 0.0001)
    }

    func testFastMovementMapsToNonZeroAmplitude() {
        var mapper = SoundMapper(settings: .default)

        let state = mapper.map(frame(speed: 1.0))

        XCTAssertFalse(state.isSilent)
        XCTAssertGreaterThan(state.amplitude, 0)
    }

    func testDefaultSensitivityKeepsOrdinaryPointerMovementSilent() {
        var mapper = SoundMapper(settings: .default)

        let state = mapper.map(frame(speed: 0.18))

        XCTAssertTrue(state.isSilent)
        XCTAssertEqual(state.amplitude, 0, accuracy: 0.0001)
    }

    func testModeratelyFastMovementBecomesAudibleWithDefaultSettings() {
        var mapper = SoundMapper(settings: .default)

        let state = mapper.map(frame(speed: 0.55))

        XCTAssertFalse(state.isSilent)
        XCTAssertGreaterThan(state.amplitude, 0.05)
        XCTAssertLessThan(state.amplitude, 0.30)
    }

    func testHorizontalPositionMapsToMinorPentatonicNotesAcrossTwoOctaves() {
        var mapper = SoundMapper(settings: .default)

        let low = mapper.map(frame(normalizedX: 0, speed: 1.0))
        let high = mapper.map(frame(timestamp: 0.1, normalizedX: 1, speed: 1.0))

        XCTAssertEqual(low.displayNoteName, "C4")
        XCTAssertEqual(high.displayNoteName, "C6")
        XCTAssertEqual(low.frequency, 261.625565, accuracy: 0.001)
        XCTAssertEqual(high.frequency, 1046.502261, accuracy: 0.001)
    }

    func testVerticalPositionIncreasesFilterBrightness() {
        var lowMapper = SoundMapper(settings: .default)
        var highMapper = SoundMapper(settings: .default)

        let low = lowMapper.map(frame(normalizedY: 0.1, speed: 1.0))
        let high = highMapper.map(frame(normalizedY: 0.9, speed: 1.0))

        XCTAssertGreaterThan(high.filterBrightness, low.filterBrightness)
    }

    func testSharpDirectionChangesTriggerChimeAccent() {
        var mapper = SoundMapper(settings: .default)

        _ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
        let accented = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))

        XCTAssertTrue(accented.accentTriggered)
        XCTAssertGreaterThan(accented.accentIntensity, 0)
    }

    func testAccentCooldownPreventsRepeatedRapidAccents() {
        var mapper = SoundMapper(settings: .default)

        _ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
        let firstAccent = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))
        let cooledDown = mapper.map(frame(timestamp: 0.4, speed: 1.0, directionAngle: 0))

        XCTAssertTrue(firstAccent.accentTriggered)
        XCTAssertFalse(cooledDown.accentTriggered)
        XCTAssertEqual(cooledDown.accentIntensity, 0, accuracy: 0.0001)
    }

    func testAccentCooldownAllowsPlayfulSharpTurnsWithoutStutter() {
        var mapper = SoundMapper(settings: .default)

        _ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
        let firstAccent = mapper.map(frame(timestamp: 0.2, speed: 1.0, directionAngle: .pi))
        let stutterBlocked = mapper.map(frame(timestamp: 0.32, speed: 1.0, directionAngle: 0))
        let playfulTurn = mapper.map(frame(timestamp: 0.40, speed: 1.0, directionAngle: .pi))

        XCTAssertTrue(firstAccent.accentTriggered)
        XCTAssertFalse(stutterBlocked.accentTriggered)
        XCTAssertTrue(playfulTurn.accentTriggered)
    }

    func testAccentDoesNotTriggerAtExactSensitivityThreshold() {
        var mapper = SoundMapper(settings: SoundaSettings(sensitivity: 0.2))

        _ = mapper.map(frame(timestamp: 0, speed: 0.2, directionAngle: 0))
        let state = mapper.map(frame(timestamp: 0.3, speed: 0.2, directionAngle: .pi))

        XCTAssertFalse(state.accentTriggered)
        XCTAssertEqual(state.accentIntensity, 0, accuracy: 0.0001)
        XCTAssertTrue(state.isSilent)
    }

    func testSilentStartupFrameDoesNotSeedDirectionForFirstMovementAccent() {
        var mapper = SoundMapper(settings: .default)

        _ = mapper.map(frame(timestamp: 0, speed: 0, directionAngle: 0))
        let firstMovement = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))

        XCTAssertFalse(firstMovement.accentTriggered)
        XCTAssertEqual(firstMovement.accentIntensity, 0, accuracy: 0.0001)
    }

    func testStoppedFrameClearsDirectionBeforeMovementResumes() {
        var mapper = SoundMapper(settings: .default)

        _ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
        _ = mapper.map(frame(timestamp: 0.1, speed: 0, directionAngle: 0))
        let resumed = mapper.map(frame(timestamp: 0.4, speed: 1.0, directionAngle: .pi))

        XCTAssertFalse(resumed.accentTriggered)
        XCTAssertEqual(resumed.accentIntensity, 0, accuracy: 0.0001)
    }

    func testZeroAccentAmountDoesNotTriggerAccentEvent() {
        var mapper = SoundMapper(settings: SoundaSettings(accentAmount: 0))

        _ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
        let state = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))

        XCTAssertFalse(state.accentTriggered)
        XCTAssertEqual(state.accentIntensity, 0, accuracy: 0.0001)
    }

    func testZeroMasterVolumeDoesNotTriggerAccentEvent() {
        var mapper = SoundMapper(settings: SoundaSettings(masterVolume: 0))

        _ = mapper.map(frame(timestamp: 0, speed: 1.0, directionAngle: 0))
        let state = mapper.map(frame(timestamp: 0.3, speed: 1.0, directionAngle: .pi))

        XCTAssertFalse(state.accentTriggered)
        XCTAssertEqual(state.accentIntensity, 0, accuracy: 0.0001)
    }

    func testStoppingMovementFadesTowardSilenceRatherThanHardCutting() {
        var mapper = SoundMapper(settings: .default)

        let moving = mapper.map(frame(timestamp: 0, speed: 1.0))
        let stopped = mapper.map(frame(timestamp: 0.1, speed: 0))

        XCTAssertGreaterThan(moving.amplitude, 0)
        XCTAssertGreaterThan(stopped.amplitude, 0)
        XCTAssertLessThan(stopped.amplitude, moving.amplitude)
        XCTAssertFalse(stopped.isSilent)
    }

    func testReleaseFadeOnlyBecomesSilentBelowOutputEpsilon() {
        var mapper = SoundMapper(settings: .default)

        _ = mapper.map(frame(timestamp: 0, speed: 1.0))
        var released = mapper.map(frame(timestamp: 0.1, speed: 0))
        for index in 1...20 {
            released = mapper.map(frame(timestamp: 0.1 + Double(index) * 0.1, speed: 0))
        }

        XCTAssertTrue(released.isSilent)
        XCTAssertEqual(released.amplitude, 0, accuracy: 0.001)
    }

    func testDisabledStateResetsTransientMapperState() {
        var mapper = SoundMapper(settings: .default)

        let carriedFilter = mapper.map(frame(timestamp: 0, normalizedY: 1, speed: 1.0)).filterBrightness
        mapper.settings = SoundaSettings(isEnabled: false)
        let disabled = mapper.map(frame(timestamp: 0.1, normalizedY: 1, speed: 1.0, directionAngle: 0))
        mapper.settings = .default
        let afterDisabled = mapper.map(frame(timestamp: 0.2, normalizedY: 0, speed: 1.0, directionAngle: .pi))

        var freshMapper = SoundMapper(settings: .default)
        let fresh = freshMapper.map(frame(timestamp: 0.2, normalizedY: 0, speed: 1.0, directionAngle: .pi))

        XCTAssertGreaterThan(carriedFilter, fresh.filterBrightness)
        XCTAssertTrue(disabled.isSilent)
        XCTAssertEqual(disabled.filterBrightness, 0, accuracy: 0.0001)
        XCTAssertFalse(afterDisabled.accentTriggered)
        XCTAssertEqual(afterDisabled.filterBrightness, fresh.filterBrightness, accuracy: 0.0001)
    }

    func testPresetsProduceDistinctNotesAtSameHorizontalPosition() {
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

        XCTAssertNotEqual(minor.displayNoteName, ragtime.displayNoteName)
        XCTAssertNotEqual(minor.displayNoteName, glass.displayNoteName)
        XCTAssertNotEqual(minor.displayNoteName, bass.displayNoteName)
        XCTAssertNotEqual(minor.displayNoteName, violin.displayNoteName)
        XCTAssertLessThan(ragtime.frequency, glass.frequency)
        XCTAssertGreaterThan(glass.frequency, minor.frequency)
        XCTAssertLessThan(bass.frequency, minor.frequency)
        XCTAssertGreaterThan(violin.frequency, minor.frequency)
        XCTAssertLessThan(violin.frequency, glass.frequency)
    }

    func testViolinLeadPresetUsesBowedLeadTimbre() {
        var mapper = SoundMapper(settings: SoundaSettings(preset: .violinLead))

        let low = mapper.map(frame(normalizedX: 0, speed: 1.0))
        let high = mapper.map(frame(timestamp: 0.1, normalizedX: 1, speed: 1.0))

        XCTAssertEqual(SoundaSettings.Preset.violinLead.displayName, "Violin lead")
        XCTAssertEqual(low.leadTimbre, .violin)
        XCTAssertEqual(high.leadTimbre, .violin)
        XCTAssertGreaterThanOrEqual(low.frequency, 293.66)
        XCTAssertLessThanOrEqual(high.frequency, 1760)
    }

    func testNonFiniteInputsMapToFiniteSafeOutput() {
        var mapper = SoundMapper(
            settings: SoundaSettings(
                masterVolume: .nan,
                sensitivity: .infinity,
                accentAmount: -.infinity
            )
        )

        let state = mapper.map(
            frame(
                timestamp: .nan,
                normalizedX: .nan,
                normalizedY: .infinity,
                speed: .nan,
                acceleration: .nan,
                directionAngle: .nan
            )
        )

        XCTAssertTrue(state.frequency.isFinite)
        XCTAssertTrue(state.amplitude.isFinite)
        XCTAssertTrue(state.filterBrightness.isFinite)
        XCTAssertTrue(state.accentIntensity.isFinite)
    }

    func testScreenSampleFeatureAccumulatorReducesPixelsToSyntheticValues() {
        var accumulator = ScreenSampleFeatureAccumulator()

        accumulator.add(red: 1, green: 0, blue: 0)
        accumulator.add(red: 0, green: 0, blue: 1)
        accumulator.add(red: 1, green: 1, blue: 1)

        let features = accumulator.finish()

        XCTAssertEqual(features.sampleCount, 3)
        XCTAssertEqual(features.meanBrightness, 5.0 / 9.0, accuracy: 0.0001)
        XCTAssertGreaterThan(features.meanSaturation, 0.6)
        XCTAssertGreaterThan(features.contrast, 0.6)
        XCTAssertEqual(features.warmth, 0, accuracy: 0.0001)
    }

    func testScreenSampleFeatureAccumulatorSanitizesInputs() {
        var accumulator = ScreenSampleFeatureAccumulator()

        accumulator.add(red: .nan, green: .infinity, blue: -.infinity)
        let features = accumulator.finish()

        XCTAssertEqual(features.sampleCount, 1)
        XCTAssertTrue(features.meanBrightness.isFinite)
        XCTAssertTrue(features.meanSaturation.isFinite)
        XCTAssertTrue(features.meanHue.isFinite)
        XCTAssertTrue(features.contrast.isFinite)
        XCTAssertTrue(features.warmth.isFinite)
    }

    func testScreenOrchestraRequiresLeadForScreenBand() {
        var mapper = ScreenOrchestraMapper()
        let lead = SoundState(
            isSilent: false,
            frequency: 440,
            amplitude: 0.5,
            filterBrightness: 0.4,
            accentTriggered: false,
            accentIntensity: 0,
            displayNoteName: "A4"
        )

        XCTAssertEqual(mapper.map(lead: lead, features: screenFeatures(), isEnabled: false), .silence)
        XCTAssertEqual(mapper.map(lead: .silence, features: screenFeatures(), isEnabled: true), .silence)
    }

    func testScreenBrightnessControlsOrchestraDensityAndLevel() {
        let lead = leadState(amplitude: 0.6)
        var dimMapper = ScreenOrchestraMapper()
        var brightMapper = ScreenOrchestraMapper()

        let dim = dimMapper.map(
            lead: lead,
            features: screenFeatures(brightness: 0.12, saturation: 0.25, contrast: 0.08),
            isEnabled: true
        )
        let bright = brightMapper.map(
            lead: lead,
            features: screenFeatures(brightness: 0.86, saturation: 0.25, contrast: 0.08),
            isEnabled: true
        )

        XCTAssertTrue(dim.isActive)
        XCTAssertTrue(bright.isActive)
        XCTAssertGreaterThan(bright.voiceCount, dim.voiceCount)
        XCTAssertGreaterThan(bright.amplitude, dim.amplitude)
        XCTAssertLessThanOrEqual(bright.amplitude, lead.amplitude * 0.35)
        XCTAssertLessThanOrEqual(bright.voiceCount, 3)
    }

    func testScreenSaturationShapesRichnessWithoutWarblyMotion() {
        let lead = leadState(amplitude: 0.6)
        var calmMapper = ScreenOrchestraMapper()
        var vividMapper = ScreenOrchestraMapper()

        let calm = calmMapper.map(
            lead: lead,
            features: screenFeatures(brightness: 0.5, saturation: 0.05, contrast: 0.04),
            isEnabled: true
        )
        let vivid = vividMapper.map(
            lead: lead,
            features: screenFeatures(brightness: 0.5, saturation: 0.95, contrast: 0.72),
            isEnabled: true
        )

        XCTAssertGreaterThan(vivid.richness, calm.richness)
        XCTAssertGreaterThan(vivid.detuneCents, calm.detuneCents)
        XCTAssertLessThanOrEqual(vivid.detuneCents, 3)
        XCTAssertLessThanOrEqual(vivid.motion, 0.12)
    }

    func testWarmAndCoolScreensChooseDifferentHarmonyColors() {
        let lead = leadState(amplitude: 0.6)
        var warmMapper = ScreenOrchestraMapper()
        var coolMapper = ScreenOrchestraMapper()

        let warm = warmMapper.map(
            lead: lead,
            features: screenFeatures(hue: 0.05, warmth: 0.7),
            isEnabled: true
        )
        let cool = coolMapper.map(
            lead: lead,
            features: screenFeatures(hue: 0.62, warmth: -0.7),
            isEnabled: true
        )

        XCTAssertNotEqual(warm.intervalSemitones, cool.intervalSemitones)
        XCTAssertTrue(warm.intervalSemitones.allSatisfy { [0, 7, 12, 14].contains($0) })
        XCTAssertTrue(cool.intervalSemitones.allSatisfy { [0, 5, 7, 12, 14].contains($0) })
    }

    func testScreenBandMapsMovementIntoGrooveEnergy() {
        var mapper = ScreenOrchestraMapper()

        let groove = mapper.map(
            lead: leadState(amplitude: 0.55),
            features: screenFeatures(brightness: 0.55, saturation: 0.35, contrast: 0.75),
            isEnabled: true
        ).groove

        XCTAssertTrue(groove.isActive)
        XCTAssertGreaterThan(groove.kickIntensity, 0.1)
        XCTAssertGreaterThan(groove.hatIntensity, 0.2)
        XCTAssertGreaterThan(groove.tempoBPM, 90)
        XCTAssertLessThanOrEqual(groove.tempoBPM, 150)
    }

    func testScreenBandGrooveWorksWithoutScreenSamples() {
        var mapper = ScreenOrchestraMapper()

        let band = mapper.map(
            lead: leadState(amplitude: 0.58),
            features: nil,
            isEnabled: true
        )

        XCTAssertFalse(band.isActive)
        XCTAssertTrue(band.groove.isActive)
        XCTAssertGreaterThan(band.groove.kickIntensity, 0.1)
        XCTAssertGreaterThan(band.groove.hatIntensity, 0.1)
    }

    func testScreenBandTurnsLeadAccentsIntoClapTriggers() {
        var mapper = ScreenOrchestraMapper()
        let groove = mapper.map(
            lead: SoundState(
                isSilent: false,
                frequency: 440,
                amplitude: 0.45,
                filterBrightness: 0.5,
                accentTriggered: true,
                accentIntensity: 0.7,
                displayNoteName: "A4"
            ),
            features: screenFeatures(brightness: 0.5, saturation: 0.4, contrast: 0.5),
            isEnabled: true
        ).groove

        XCTAssertTrue(groove.clapTriggered)
        XCTAssertGreaterThan(groove.snareIntensity, 0.5)
    }

    func testScreenOrchestraMapperSanitizesNonFiniteFeatures() {
        var mapper = ScreenOrchestraMapper()
        let orchestra = mapper.map(
            lead: leadState(amplitude: .infinity, frequency: .nan),
            features: ScreenSampleFeatures(
                sampleCount: 12,
                meanBrightness: .nan,
                meanSaturation: .infinity,
                meanHue: -.infinity,
                contrast: .nan,
                warmth: .infinity
            ),
            isEnabled: true
        )

        XCTAssertFalse(orchestra.isActive)
        XCTAssertTrue(orchestra.rootFrequency.isFinite)
        XCTAssertTrue(orchestra.amplitude.isFinite)
        XCTAssertTrue(orchestra.richness.isFinite)
        XCTAssertTrue(orchestra.motion.isFinite)
        XCTAssertTrue(orchestra.detuneCents.isFinite)
        XCTAssertTrue(orchestra.groove.kickIntensity.isFinite)
        XCTAssertTrue(orchestra.groove.snareIntensity.isFinite)
        XCTAssertTrue(orchestra.groove.hatIntensity.isFinite)
        XCTAssertTrue(orchestra.groove.tempoBPM.isFinite)
        XCTAssertGreaterThanOrEqual(orchestra.voiceCount, 0)
        XCTAssertLessThanOrEqual(orchestra.voiceCount, 4)
    }
}
#else
func soundMapperAssertions() {
    var mapper = SoundMapper(settings: SoundaSettings(sensitivity: 0.4))
    precondition(mapper.map(frame(speed: 0.1)).isSilent)

    mapper = SoundMapper(settings: .default)
    precondition(mapper.map(frame(speed: 1.0)).amplitude > 0)
}
#endif

private func frame(
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

private func leadState(
    amplitude: Double,
    frequency: Double = 440
) -> SoundState {
    SoundState(
        isSilent: amplitude <= 0,
        frequency: frequency,
        amplitude: amplitude,
        filterBrightness: 0.5,
        accentTriggered: false,
        accentIntensity: 0,
        displayNoteName: "A4"
    )
}

private func screenFeatures(
    sampleCount: Int = 576,
    brightness: Double = 0.5,
    saturation: Double = 0.5,
    hue: Double = 0.2,
    contrast: Double = 0.3,
    warmth: Double = 0.1
) -> ScreenSampleFeatures {
    ScreenSampleFeatures(
        sampleCount: sampleCount,
        meanBrightness: brightness,
        meanSaturation: saturation,
        meanHue: hue,
        contrast: contrast,
        warmth: warmth
    )
}
