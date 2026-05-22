# Sounda Menu Bar Instrument Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use $subagent-driven-development (recommended) or $executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a CLI-buildable macOS menu bar instrument that turns expressive cursor movement into a lead synth voice plus chime accents.

**Architecture:** Start with a Swift Package executable so the project can build with the currently available Swift command-line tools. Keep musical mapping in a pure `SoundaCore` library, and keep AppKit cursor/menu-bar code plus AVAudioEngine synthesis in the executable target. Color sampling stays out of the MVP unless the cursor instrument is already working.

**Tech Stack:** Swift Package Manager, Swift, AppKit `NSStatusItem`, AppKit `NSEvent.mouseLocation`, AVFAudio `AVAudioEngine`, AVFAudio `AVAudioSourceNode`, XCTest where available, and a CLI smoke runner for CommandLineTools environments without XCTest or Swift Testing.

---

## Plan Notes

This plan is intentionally goal-oriented rather than code-prescriptive. The implementor should make reasonable Swift implementation choices inside the boundaries below. Preserve the architecture and acceptance criteria; do not spend hackathon time on public packaging, signing, notarization, or color sampling before the core cursor instrument works.

## File Structure

- Create `Package.swift`: defines `SoundaCore`, `SoundaApp`, `SoundaCoreSmokeTests`, and `SoundaCoreTests`.
- Create `Sources/SoundaCore/CursorFrame.swift`: pure cursor movement input model.
- Create `Sources/SoundaCore/SoundState.swift`: pure musical output model consumed by audio.
- Create `Sources/SoundaCore/SoundaSettings.swift`: volume, sensitivity, accent amount, preset.
- Create `Sources/SoundaCore/SoundMapper.swift`: movement-to-music mapping and accent cooldown.
- Create `Sources/SoundaApp/main.swift`: starts `NSApplication` and wires app services.
- Create `Sources/SoundaCoreSmokeTests/main.swift`: executable smoke runner for toolchains where `swift test` only builds because XCTest and Swift Testing are unavailable.
- Create `Sources/SoundaApp/AppDelegate.swift`: lifecycle owner for menu bar, tracker, mapper, audio.
- Create `Sources/SoundaApp/MenuBarController.swift`: AppKit status item and popover controls.
- Create `Sources/SoundaApp/CursorTracker.swift`: polls global cursor location and emits `CursorFrame`.
- Create `Sources/SoundaApp/AudioEngineController.swift`: owns `AVAudioEngine` and generated synth/chime audio.
- Create `Sources/SoundaApp/DiagnosticsRunner.swift`: deterministic cursor-to-audio self-test harness.
- Create `Tests/SoundaCoreTests/SoundMapperTests.swift`: regression tests for the musical mapping.
- Modify `README.md`: short run instructions and demo checklist.

## Task 1: Bootstrap A Buildable Swift Package

**Files:**
- Create: `Package.swift`
- Create: `Sources/SoundaCore/SoundaSettings.swift`
- Create: `Sources/SoundaCore/CursorFrame.swift`
- Create: `Sources/SoundaCore/SoundState.swift`
- Create: `Sources/SoundaCore/SoundMapper.swift`
- Create: `Sources/SoundaApp/main.swift`
- Create: `Sources/SoundaCoreSmokeTests/main.swift`
- Create: `Tests/SoundaCoreTests/SoundMapperTests.swift`

- [x] **Step 1: Create the package manifest**
  - Define a macOS-only Swift package.
  - Define library target `SoundaCore`.
  - Define executable target `SoundaApp` depending on `SoundaCore`.
  - Define executable target `SoundaCoreSmokeTests` depending on `SoundaCore`.
  - Define test target `SoundaCoreTests` depending on `SoundaCore`.
  - Avoid third-party dependencies.

- [x] **Step 2: Add minimal bootstrap types**
  - Add small compile-ready versions of `SoundaSettings`, `CursorFrame`, `SoundState`, and `SoundMapper`.
  - `SoundMapper` can return silence for now.
  - Keep all types in `SoundaCore` free of AppKit and AVFAudio imports.

- [x] **Step 3: Add a minimal executable**
  - `Sources/SoundaApp/main.swift` should import Foundation/AppKit and print or log that Sounda starts.
  - It does not need to create the menu bar item yet.

- [x] **Step 4: Add a smoke test**
  - Add one XCTest that constructs `SoundMapper` with default settings and maps a basic cursor frame without crashing for full Xcode/XCTest environments.
  - Add a `SoundaCoreSmokeTests` executable that constructs `SoundMapper`, maps a basic cursor frame, asserts the expected silent bootstrap state, prints a concise success message, and exits non-zero on failure.

- [x] **Step 5: Verify**
  - Run: `swift build`
  - Expected: package builds.
  - Run: `swift test`
  - Expected: package test target remains compatible. In the current CommandLineTools environment, XCTest and Swift Testing are unavailable, so this may only build the test target.
  - Run: `swift run SoundaCoreSmokeTests`
  - Expected: smoke assertion executes and prints `SoundaCore smoke test passed`.

- [x] **Step 6: Commit**
  - Commit message: `chore: scaffold Swift package`

## Task 2: Implement The Pure Sound Mapping Core

**Files:**
- Modify: `Sources/SoundaCore/CursorFrame.swift`
- Modify: `Sources/SoundaCore/SoundState.swift`
- Modify: `Sources/SoundaCore/SoundaSettings.swift`
- Modify: `Sources/SoundaCore/SoundMapper.swift`
- Modify: `Tests/SoundaCoreTests/SoundMapperTests.swift`

- [x] **Step 1: Define stable core models**
  - `CursorFrame` should carry timestamp, normalized X/Y, speed, acceleration, and direction angle.
  - `SoundState` should carry enabled/silent state, frequency, amplitude, filter brightness, accent trigger, accent intensity, and display note name.
  - `SoundaSettings` should carry enabled, master volume, sensitivity, accent amount, and preset.

- [x] **Step 2: Add mapping tests**
  - Slow movement below sensitivity maps to silence.
  - Fast movement maps to non-zero amplitude.
  - Horizontal position maps to a minor pentatonic note across two octaves.
  - Vertical position increases filter brightness.
  - Sharp direction changes trigger a chime accent.
  - Accent cooldown prevents repeated rapid accents.
  - Stopping movement fades toward silence rather than hard-cutting.

- [x] **Step 3: Implement the mapper**
  - Use a minor pentatonic scale as the default preset.
  - Clamp normalized inputs defensively.
  - Smooth amplitude/filter output enough to avoid jitter.
  - Track previous direction and last accent time inside `SoundMapper`.
  - Keep the mapper deterministic under fake timestamps.

- [x] **Step 4: Verify**
  - Run: `swift test`
  - Expected: all `SoundaCoreTests` pass.

- [x] **Step 5: Commit**
  - Commit message: `feat: map cursor movement to sound state`

## Task 3: Add Global Cursor Tracking

**Files:**
- Create: `Sources/SoundaApp/CursorTracker.swift`
- Modify: `Sources/SoundaApp/main.swift`

- [x] **Step 1: Implement cursor polling**
  - Poll `NSEvent.mouseLocation` on a timer around 60 Hz.
  - Normalize X/Y against the active screen frame, falling back to the main screen.
  - Compute speed, acceleration, and direction from consecutive samples.
  - Emit `CursorFrame` through a callback closure.

- [x] **Step 2: Add a temporary debug run path**
  - Wire `CursorTracker` from `main.swift`.
  - Log a compact line for movement intensity or normalized coordinates while running.
  - Keep the process alive through `NSApplication`.

- [x] **Step 3: Verify**
  - Run: `swift run SoundaApp`
  - Expected: process starts and cursor movement produces debug output.
  - Stop manually with `Ctrl-C` if no menu bar quit control exists yet.

- [x] **Step 4: Commit**
  - Commit message: `feat: track global cursor movement`

## Task 4: Add Menu Bar Controls

**Files:**
- Create: `Sources/SoundaApp/AppDelegate.swift`
- Create: `Sources/SoundaApp/MenuBarController.swift`
- Modify: `Sources/SoundaApp/main.swift`

- [ ] **Step 1: Introduce app lifecycle ownership**
  - Move startup wiring into `AppDelegate`.
  - Keep references to `MenuBarController`, `CursorTracker`, `SoundMapper`, and settings.
  - Ensure the app can quit cleanly from a menu item or popover action.

- [ ] **Step 2: Create the status bar item**
  - Use `NSStatusBar.system.statusItem`.
  - Give it a recognizable short title or system image.
  - Clicking the item should open a compact control popover or menu.

- [ ] **Step 3: Add MVP controls**
  - Enable/mute toggle.
  - Master volume slider.
  - Sensitivity slider.
  - Accent amount slider.
  - Preset selector with two or three options.
  - Readout for current movement intensity and note name.
  - Show color mode as disabled or experimental; do not implement sampling yet.

- [ ] **Step 4: Wire settings**
  - Control changes should update shared `SoundaSettings`.
  - Cursor frames should map through `SoundMapper` using current settings.
  - The debug readout should update from the latest `SoundState`.

- [ ] **Step 5: Verify**
  - Run: `swift run SoundaApp`
  - Expected: menu bar item appears.
  - Expected: controls open, settings change, and quit works.

- [ ] **Step 6: Commit**
  - Commit message: `feat: add menu bar control surface`

## Task 5: Add Native Audio Synthesis

**Files:**
- Create: `Sources/SoundaApp/AudioEngineController.swift`
- Modify: `Sources/SoundaApp/AppDelegate.swift`
- Modify: `Sources/SoundaApp/MenuBarController.swift`

- [ ] **Step 1: Build the audio controller**
  - Own an `AVAudioEngine`.
  - Use `AVAudioSourceNode` to generate the lead voice from the latest `SoundState`.
  - Keep audio render state thread-safe and lightweight.
  - Expose start, stop, mute/update-state, and error state.

- [ ] **Step 2: Implement the lead synth**
  - Generate a simple sine or triangle-like voice.
  - Use `SoundState.frequency` and `SoundState.amplitude`.
  - Apply smooth amplitude changes to avoid clicks.
  - Keep the dry voice working before adding effects.

- [ ] **Step 3: Implement chime accents**
  - Trigger short decaying sine bursts from `SoundState` accent events.
  - Respect accent amount and master volume.
  - Avoid unbounded accent accumulation.

- [ ] **Step 4: Wire audio to app state**
  - Start audio when Sounda is enabled.
  - Send updated `SoundState` from cursor tracking into `AudioEngineController`.
  - Stop or silence audio when muted.
  - Surface audio startup failures in the control popover.

- [ ] **Step 5: Verify**
  - Run: `swift run SoundaApp`
  - Expected: enabling Sounda starts audio.
  - Expected: fast cursor movement fades in the lead voice.
  - Expected: sharp turns produce chime accents.
  - Expected: mute and volume work.
  - Run: `swift test`
  - Expected: core mapping tests still pass.

- [ ] **Step 6: Commit**
  - Commit message: `feat: synthesize cursor-driven audio`

## Task 6: Add E2E Diagnostics

**Files:**
- Create: `Sources/SoundaApp/DiagnosticsRunner.swift`
- Modify: `Sources/SoundaApp/AudioEngineController.swift`
- Modify: `Sources/SoundaApp/main.swift`
- Modify: `Sources/SoundaApp/AppDelegate.swift`
- Modify: `README.md`

- [ ] **Step 1: Add deterministic cursor replay**
  - Add a diagnostics path that replays a short sequence of synthetic `CursorFrame` values through `SoundMapper`.
  - Include at least three replay segments: still/slow movement, fast horizontal movement, and sharp direction changes.
  - Prefer a command-line flag such as `swift run SoundaApp --self-test` so this can run without manually using the menu bar.

- [ ] **Step 2: Add audio observability**
  - Measure sound generation inside the app process rather than through the microphone or speakers.
  - Acceptable approaches: install an audio tap on the mixer/source path and measure RMS/peak values from `AVAudioPCMBuffer`, or expose a lightweight debug meter from the same synth renderer used by `AVAudioSourceNode`.
  - The self-test should distinguish expected silence from expected audible output.

- [ ] **Step 3: Add an optional real-pointer smoke command**
  - If practical, add a separately named debug command for posting a small Core Graphics mouse movement sequence.
  - Keep this opt-in only; never move the user's pointer during normal tests.
  - If Accessibility/security permissions block it, report a clear skipped/manual status rather than failing the core test suite.

- [ ] **Step 4: Verify**
  - Run: `swift run SoundaApp --self-test`
  - Expected: slow replay reports silence, fast replay reports non-zero audio, sharp-turn replay reports chime/accent activity.
  - Run: `swift test`
  - Expected: core mapping tests still pass.

- [ ] **Step 5: Commit**
  - Commit message: `test: add cursor audio diagnostics`

## Task 7: Tune The Demo Loop

**Files:**
- Modify: `Sources/SoundaCore/SoundMapper.swift`
- Modify: `Sources/SoundaCore/SoundaSettings.swift`
- Modify: `Sources/SoundaApp/MenuBarController.swift`
- Modify: `Sources/SoundaApp/AudioEngineController.swift`
- Modify: `Tests/SoundaCoreTests/SoundMapperTests.swift`

- [ ] **Step 1: Tune defaults**
  - Sensitivity should keep ordinary small pointer movement quiet.
  - Fast movement should become audible quickly.
  - Accent cooldown should make sharp turns fun without stutter.
  - Default volume should be audible but not startling.

- [ ] **Step 2: Tune controls**
  - Slider ranges should make meaningful differences.
  - Presets should be clearly different but not require a complex sound engine.
  - The readout should remain useful and not visually noisy.

- [ ] **Step 3: Re-run regression tests**
  - Run: `swift test`
  - Expected: all tests pass after tuning.

- [ ] **Step 4: Manual demo verification**
  - Enable Sounda from the menu bar.
  - Move slowly: quiet.
  - Move quickly: lead voice fades in.
  - Make sharp turns: chime accents trigger.
  - Change volume, sensitivity, and accent amount live.
  - Toggle mute: silence.
  - Quit from the menu bar.

- [ ] **Step 5: Commit**
  - Commit message: `fix: tune Sounda demo responsiveness`

## Task 8: Document Running And Demoing Sounda

**Files:**
- Modify: `README.md`
- Optionally modify: `docs/superpowers/specs/2026-05-22-sounda-menu-bar-instrument-design.md` if implementation decisions materially differ from the approved design.

- [ ] **Step 1: Update README**
  - Explain what Sounda does in one short paragraph.
  - Add prerequisites: macOS, Swift command-line tools.
  - Add run command: `swift run SoundaApp`.
  - Add self-test command: `swift run SoundaApp --self-test`.
  - Add the manual demo checklist.
  - Note that color mode is intentionally not part of the MVP unless it was implemented.

- [ ] **Step 2: Verify docs and build**
  - Run: `swift test`
  - Expected: tests pass.
  - Run: `swift build`
  - Expected: build passes.
  - Run: `git diff --check`
  - Expected: no whitespace errors.

- [ ] **Step 3: Commit**
  - Commit message: `docs: explain Sounda demo workflow`

## Optional Task 9: Add Color Mode Only If Time Remains

**Files:**
- Create: `Sources/SoundaApp/ScreenSampler.swift`
- Modify: `Sources/SoundaCore/SoundState.swift`
- Modify: `Sources/SoundaCore/SoundMapper.swift`
- Modify: `Sources/SoundaApp/AppDelegate.swift`
- Modify: `Sources/SoundaApp/MenuBarController.swift`

- [ ] **Step 1: Decide whether to proceed**
  - Only start this task after Tasks 1-7 are complete and the movement-only demo is fun.
  - Skip this task if screen recording permission or ScreenCaptureKit setup threatens the demo timeline.

- [ ] **Step 2: Add guarded screen sampling**
  - Use ScreenCaptureKit to sample screen color near the cursor.
  - Keep sampling lower-frequency than cursor tracking.
  - Disable the feature cleanly if permission is unavailable.

- [ ] **Step 3: Use color only as a modifier**
  - Hue changes timbre.
  - Brightness changes filter brightness.
  - Saturation changes accent density.
  - Movement remains the primary instrument input.

- [ ] **Step 4: Verify graceful failure**
  - Run without screen recording permission.
  - Expected: movement-only Sounda still works.
  - Expected: color mode control explains that permission is unavailable or restart is needed.

- [ ] **Step 5: Commit**
  - Commit message: `feat: add experimental color mode`

## Completion Criteria

- `swift test` passes.
- `swift build` passes.
- `swift run SoundaApp --self-test` passes and reports silence/audible/accent checks.
- `swift run SoundaApp` starts a menu bar process.
- Menu bar controls can enable/mute, adjust volume, adjust sensitivity, adjust accent amount, switch preset, and quit.
- Fast cursor motion produces a musical lead voice.
- Sharp direction changes produce chime accents with cooldown.
- Small ordinary cursor movement stays quiet.
- README explains how to run and demo the project.
- Color mode is either explicitly absent from the MVP or implemented as optional graceful degradation.
