# Screen Orchestra Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use $subagent-driven-development (recommended) or $executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a low-cost screen-derived orchestra layer that gives the cursor instrument harmonic body without turning screen sampling into recording or video capture.

**Architecture:** Keep cursor motion as the lead voice. Reduce a tiny screen region under the pointer into synthetic features at low rate, smooth those features, map them into a quiet orchestra state in `SoundaCore`, then render that state as a capped pad layer inside the existing `AVAudioSourceNode`.

**Tech Stack:** Swift, SwiftPM, AppKit, AVFoundation, ScreenCaptureKit, XCTest.

---

### Task 1: Deterministic Musical Mapping

**Files:**
- Create: `Sources/SoundaCore/ScreenOrchestraState.swift`
- Create: `Sources/SoundaCore/ScreenOrchestraMapper.swift`
- Modify: `Sources/SoundaCore/SoundState.swift`
- Modify: `Sources/SoundaCoreSmokeTests/main.swift`
- Test: `Tests/SoundaCoreTests/SoundMapperTests.swift`

- [x] Add failing tests for mapping screen features into a quiet, finite, screen-derived orchestra state.
- [x] Implement `ScreenOrchestraState` and `ScreenOrchestraMapper`.
- [x] Extend `SoundState` so the app can deliver lead and orchestra data together.
- [x] Update smoke coverage for the pure mapper.

### Task 2: Low-Rate Screen Sensor

**Files:**
- Create: `Sources/SoundaApp/ScreenRegionSensor.swift`
- Modify: `Sources/SoundaApp/AppDelegate.swift`
- Reuse patterns from: `Sources/SoundaApp/ScreenSamplerBenchmarkRunner.swift`

- [x] Add a live ScreenCaptureKit sensor using a 96x96 point crop, 24x24 output, 6 Hz interval, no cursor, no audio, and queue depth 1.
- [x] Reduce each sample to `ScreenSampleFeatures` immediately and discard the raw buffer.
- [x] Keep the sensor permission-aware so the app keeps working when Screen Recording permission is absent.

### Task 3: Audio Orchestra Renderer

**Files:**
- Modify: `Sources/SoundaApp/AudioEngineController.swift`

- [x] Add 2-4 quiet pad voices to the render state.
- [x] Keep orchestra volume capped below the lead and smooth attack/release so screen changes bloom instead of flicker.
- [x] Use hue/warmth/contrast/saturation-derived state for intervals, detune, brightness, and tremolo.

### Task 4: Controls And Verification

**Files:**
- Modify: `Sources/SoundaCore/SoundaSettings.swift`
- Modify: `Sources/SoundaApp/MenuBarController.swift`
- Modify: `Sources/SoundaApp/AppDelegate.swift`

- [x] Replace the disabled color checkbox with a working `Screen orchestra` toggle.
- [x] Surface whether the screen layer is active, unavailable, or off.
- [x] Run `swift test`, `swift run SoundaCoreSmokeTests`, `swift run SoundaApp --self-test`, and `swift build`.
