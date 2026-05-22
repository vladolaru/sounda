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

        let minor = minorMapper.map(frame(normalizedX: 0.75, speed: 1.0))
        let ragtime = ragtimeMapper.map(frame(normalizedX: 0.75, speed: 1.0))
        let glass = glassMapper.map(frame(normalizedX: 0.75, speed: 1.0))
        let bass = bassMapper.map(frame(normalizedX: 0.75, speed: 1.0))

        XCTAssertNotEqual(minor.displayNoteName, ragtime.displayNoteName)
        XCTAssertNotEqual(minor.displayNoteName, glass.displayNoteName)
        XCTAssertNotEqual(minor.displayNoteName, bass.displayNoteName)
        XCTAssertLessThan(ragtime.frequency, glass.frequency)
        XCTAssertGreaterThan(glass.frequency, minor.frequency)
        XCTAssertLessThan(bass.frequency, minor.frequency)
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
