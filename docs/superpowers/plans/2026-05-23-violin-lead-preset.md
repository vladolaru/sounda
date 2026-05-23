# Violin Lead Preset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use $subagent-driven-development (recommended) or $executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Violin lead` preset that gives Sounda a bowed, groove-aligned lead sound.

**Architecture:** Extend `SoundaSettings.Preset` and `SoundState` with a lead timbre signal, map the new preset to a violin-friendly range, and render that timbre in `AudioEngineController` with saw/triangle harmonics, soft bow envelope, and subtle vibrato. Keep the existing groove-lock behavior intact.

**Tech Stack:** Swift, SwiftPM, SoundaCore, AVFoundation, smoke/self-test diagnostics.

---

### Task 1: Core Preset And State

**Files:**
- Modify: `Sources/SoundaCore/SoundaSettings.swift`
- Modify: `Sources/SoundaCore/SoundState.swift`
- Modify: `Sources/SoundaCore/SoundMapper.swift`
- Test: `Tests/SoundaCoreTests/SoundMapperTests.swift`
- Test: `Sources/SoundaCoreSmokeTests/main.swift`

- [x] Add tests proving `Violin lead` appears as a preset, maps to a higher bowed range, and sets a violin lead timbre.
- [x] Add the preset enum case and propagate `leadTimbre` through `SoundState`.
- [x] Map the preset to a violin-friendly scale.

### Task 2: Audio Renderer

**Files:**
- Modify: `Sources/SoundaApp/AudioEngineController.swift`
- Modify: `Sources/SoundaApp/DiagnosticsRunner.swift`

- [x] Add failing diagnostics for a violin timbre probe.
- [x] Render the violin timbre with bowed harmonics and subtle vibrato while preserving groove latching.
- [x] Verify with build, smoke, tests, and self-test.
