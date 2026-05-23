# Screen Band Tuning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use $subagent-driven-development (recommended) or $executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the warbly screen pad feel with calmer chords and a small synthetic drum/groove layer.

**Architecture:** Keep cursor motion as the lead. Keep screen sampling as synthetic feature input only. Map screen features and cursor motion into a “screen band” state: stable support chords plus quantized drum energy. Render both inside the existing audio source node without samples or file assets.

**Tech Stack:** Swift, SwiftPM, AVFoundation, ScreenCaptureKit, XCTest/smoke executable.

---

### Task 1: Core Music State

**Files:**
- Modify: `Sources/SoundaCore/ScreenOrchestraState.swift`
- Modify: `Sources/SoundaCore/ScreenOrchestraMapper.swift`
- Modify: `Sources/SoundaCore/SoundState.swift`
- Test: `Tests/SoundaCoreTests/SoundMapperTests.swift`
- Test: `Sources/SoundaCoreSmokeTests/main.swift`

- [x] Add tests that cap chord motion/detune and prefer stable fifth/octave/sus intervals.
- [x] Add tests for a groove state where speed controls hat/kick energy and direction changes trigger clap/snare energy.
- [x] Implement the mapper changes with low modulation and finite/safe output.

### Task 2: Audio Renderer

**Files:**
- Modify: `Sources/SoundaApp/AudioEngineController.swift`
- Modify: `Sources/SoundaApp/DiagnosticsRunner.swift`

- [x] Reduce pad tremolo to near-static shimmer.
- [x] Add synthetic kick, clap/snare, and hi-hat voices.
- [x] Add self-test render probes for the calmer chord bed and drums.

### Task 3: Runtime Wiring

**Files:**
- Modify: `Sources/SoundaApp/AppDelegate.swift`
- Modify: `Sources/SoundaApp/MenuBarController.swift` if status text needs adjustment.

- [x] Feed cursor speed/accent state into the screen band mapper.
- [x] Restart the running menu bar app after verification so the user can hear the tuning.
