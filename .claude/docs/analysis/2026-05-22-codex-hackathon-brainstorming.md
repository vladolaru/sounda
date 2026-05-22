Last updated: 2026-05-22 18:44

> **Prompt:** "$brainstorming You are a thinking partner with a technical product streak. You goal is to help me quickly shape a hackathon project that is meant to be shipped really fast and be really fun."
> **Follow-up:** "My idea goes like this: have a MacOS app (or a background process if it works) that will generate various musical sounds depending on mouse movements (speed, etc) and maybe what is underneeth the mouse cursor (colors, etc)"
> **Follow-up:** "A"
> **Follow-up:** "If we can have a menu bar tool even better"
> **Follow-up:** "Just some place to have some controls"
> **Follow-up:** "preferably an instrument but we can go with having parallel sound tracks that are controlled/modified by various (triggers)"
> **Follow-up:** "C"
> **Follow-up:** "c"
> **Follow-up:** "WDyt?"
> **Follow-up:** "yes"
> **Follow-up:** "wdyt is most fun and impressive and doable?"
> **Follow-up:** "ok"
> **Follow-up:** "yes"
> **Follow-up:** "yes"
> **Follow-up:** "yes"
> **Follow-up:** "yes"
> **Follow-up:** "yes"
> **Follow-up:** "self review. If you need to search the web to ground your approach and available libraries and such do it"
> **Follow-up:** "approve"
> **Follow-up:** "First. Are there ways you can test things e2e? Detect the sounds, move my mouse, etc?"

# Hackathon Brainstorming Notes

## Repository Context

- Current project path: `/Users/vladolaru/Work/personal/sounda`
- Git branch/status: `main`, clean relative to `origin/main` before this note was created.
- Recent history: one commit, `1166c0a Initial commit`.
- Files found during initial scan: `README.md`.
- `README.md` currently says:
  - Project name: `sounda`
  - Description: `Cool sounds`

## Initial Product Read

- The repo is effectively blank, so the hackathon shape can still be chosen freely.
- The name and README point toward an audio/sound-centered project.
- Because the user emphasized "shipped really fast" and "really fun", the design should bias toward a narrow, demoable loop rather than a broad platform.
- The concrete idea is a local macOS experience that turns cursor motion, speed, and possibly sampled screen color under the cursor into live musical output.
- The likely constraints are macOS permissions, low-latency audio generation, and making the mapping feel musical instead of random.

## Open Questions

- Ship target: reliable demo on the user's Mac first.
- Preferred wrapper if feasible: menu bar tool, because it fits the background-process feel without making packaging the main project.
- UI expectation: not a full app surface; provide a small place for controls, likely via menu bar popover/window, while the core experience runs globally.
- Sound direction: prefer something that feels like an instrument. Parallel sound tracks/layers are acceptable if each is controlled or modified by distinct triggers rather than acting as disconnected effects.
- Input priority: movement first, with screen color under the cursor as an optional experimental toggle. The MVP should still work well if color sampling is disabled or unavailable.
- Implementation posture: choose whatever ships fastest from this repo. Native menu bar polish is desirable, but the first priority is a reliable local demo.
- Interaction recommendation: prefer always-on while enabled, but gated by expressive movement thresholds. This keeps the "my computer became an instrument" feeling while avoiding constant jitter/noise during ordinary pointer use.
- Confirmed interaction model: always-on while enabled, with movement thresholding and a menu bar/control-surface mute or enable toggle.
- Sound palette recommendation: synth instrument core with a small percussive/glitch accent layer. This is likely more impressive than pure minimal synth, more controllable than ambient pads, and easier to ship than a full playful chiptune composition system.
- User accepted the synth-plus-accents direction.
- User approved shaping the design around a Swift menu bar app with a ruthlessly small first milestone: global cursor tracking, one synth voice, one accent layer, and menu bar controls.
- User approved the core product shape: a tiny macOS menu bar instrument with gated global cursor tracking, one lead voice, one accent layer, core controls, and optional color mode as a bonus.
- User approved the proposed architecture/data flow: MenuBarApp, CursorTracker, SoundMapper, AudioEngine, and optional ScreenSampler as separate units.
- User approved the musical mapping: constrained scale-based lead voice, speed-driven intensity, direction/acceleration accents, smooth fade-out below threshold, and color as modifier only.
- User approved the final design section covering permissions, failure modes, and pragmatic testing.

## Spec Artifact

- Written design spec: `docs/superpowers/specs/2026-05-22-sounda-menu-bar-instrument-design.md`
- Self-review tightened ambiguous mapping choices:
  - Horizontal cursor position selects notes across two octaves.
  - Vertical cursor position controls filter brightness.
  - Hue changes timbre if color mode is implemented.
  - Direction changes trigger chime accents.
  - The default scale is minor pentatonic.

## Grounded Self-Review

### Sources Checked

- Apple developer documentation for `MenuBarExtra`: confirms a SwiftUI menu bar scene exists on macOS 13+.
- Apple developer documentation for `NSStatusBar` and `NSStatusItem`: confirms AppKit can create status bar items in the system-wide menu bar.
- Apple developer documentation for `NSEvent.mouseLocation`: confirms it reports the current mouse position in screen coordinates.
- Apple developer documentation for `AVAudioEngine`: confirms it manages real-time audio node graphs and supports `start()`, `prepare()`, and attached nodes.
- Apple developer documentation for `AVAudioSourceNode`: confirms it supplies generated audio data and is available on macOS 10.15+.
- Apple developer documentation for ScreenCaptureKit: confirms it supports high-performance screen capture on macOS 12.3+.
- Apple ScreenCaptureKit sample: confirms screen recording permission is prompted on first run and may require restart after granting permission.
- Context7 AudioKit docs: confirms AudioKit offers `AudioEngine` and oscillator abstractions with frequency/amplitude parameters.
- Local environment check: macOS 26.5, Swift CLI 6.3.2 available, full Xcode app not selected for `xcodebuild`.

### Findings

- The original native direction is viable.
- The original spec was too implicit about the menu bar implementation. `MenuBarExtra` is elegant, but the current local environment favors a Swift Package executable using AppKit `NSStatusItem`, with SwiftUI hosted in a popover if useful.
- The original spec was too broad on audio implementation. Native `AVAudioEngine` + `AVAudioSourceNode` is enough for the first synth and chime accents. AudioKit is useful, but it should remain a fallback to avoid dependency and setup overhead.
- The original spec correctly treated color mode as optional. ScreenCaptureKit and screen recording permission make it the riskiest part of the demo.

### Spec Updates Applied

- Added a build/toolchain constraint: start with a Swift Package executable and AppKit status item.
- Updated `MenuBarApp` to own an AppKit status bar item/control popover.
- Updated `AudioEngine` to explicitly use `AVAudioEngine` and `AVAudioSourceNode`.
- Added an `Audio Implementation` section that keeps AudioKit as an optional fallback.
- Updated color mode to use ScreenCaptureKit and handle screen recording permission/restart states gracefully.

## E2E Testing Strategy

- The implementation should include deterministic e2e-style checks that replay synthetic cursor movement into the same mapper/audio path used by the app. This is more reliable than moving the user's pointer during automated tests.
- Sound can be detected in-process by measuring generated audio buffers, not by listening through the microphone or system speakers. Apple audio APIs support audio taps on nodes, and `AVAudioPCMBuffer` exposes sample data that can be reduced to RMS/peak metrics.
- Real mouse movement is technically possible through Core Graphics mouse events, but it should be a manual smoke test or explicit debug command only because it can steal the user's pointer and may hit Accessibility/security permissions.
- Full speaker-output detection would require a virtual audio device such as BlackHole or a loopback driver, which is unnecessary for the MVP and too much setup for the hackathon path.
- Plan update needed: add a focused e2e diagnostics task before final tuning/documentation.
