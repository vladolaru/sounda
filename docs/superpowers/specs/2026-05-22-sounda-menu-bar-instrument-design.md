# Sounda Menu Bar Instrument Design

Last updated: 2026-05-22 18:33

## Purpose

Sounda is a tiny macOS menu bar instrument that turns expressive cursor movement into musical sound. The hackathon target is a reliable demo on one Mac, not a polished public release. The demo should feel immediate: enable Sounda, move the cursor, and the desktop becomes playable.

## Product Shape

Sounda runs from the macOS menu bar and exposes a small control popover. It does not require a dedicated performance window. When enabled, it observes global cursor movement and converts deliberate motion into sound. Small ordinary pointer movements stay quiet; faster or sharper movement fades in a musical response.

The first demo includes:

- Menu bar item with a small control popover.
- Enable/mute toggle.
- Master volume control.
- Sensitivity threshold control.
- One lead synth voice driven by cursor position and speed.
- One accent layer triggered by sharp movement changes.
- Optional experimental color mode, disabled by default until movement-only playback feels good.

## Architecture

Use a small native Swift macOS app. For the hackathon build, start as a Swift Package executable that creates an AppKit status bar item and runs an `NSApplication` event loop. This fits the current local toolchain, which has the Swift command-line tools available but does not have the full Xcode app selected for `xcodebuild`.

SwiftUI can still be used for the control surface by hosting a SwiftUI view in an AppKit popover. A full Xcode project, `MenuBarExtra` scene, signed `.app` bundle, or installer can come later if the demo needs packaging.

Keep the system split into focused units so the sound mapping can be tuned quickly without touching platform or audio code.

- `MenuBarApp`: owns the AppKit status bar item and control popover.
- `CursorTracker`: samples global mouse location and computes movement features.
- `SoundMapper`: converts movement features into musical state.
- `AudioEngine`: owns `AVAudioEngine` and `AVAudioSourceNode` audio generation for the lead synth and accents.
- `ScreenSampler`: optional color sampler used only when color mode is enabled.

Core data flow:

```text
CursorTracker -> CursorFrame -> SoundMapper -> SoundState -> AudioEngine
```

Optional color data flow:

```text
ScreenSampler -> ColorFrame -> SoundMapper
```

The audio engine must not depend on macOS cursor APIs. It receives musical state only: pitch, intensity, timbre, and accent events.

## Musical Mapping

The MVP should sound musical before it is clever. Raw cursor values should be constrained into a small musical system.

- Horizontal cursor position, normalized across the active screen, selects notes from a fixed scale across two octaves.
- Vertical cursor position controls filter brightness.
- Cursor speed controls volume and synth brightness.
- Acceleration controls accent likelihood.
- Direction changes trigger short chime accents.
- Accent triggers use a cooldown to avoid stutter.
- When movement drops below the sensitivity threshold, the sound fades out smoothly.

Default scale should be minor pentatonic. That keeps movement expressive without producing harsh note clashes.

## Audio Implementation

Use native Apple audio APIs for the MVP:

- `AVAudioEngine` owns the real-time audio graph.
- `AVAudioSourceNode` generates the lead synth from the latest `SoundState`.
- Short chime accents are generated as decaying sine bursts inside the same source node or a second lightweight source node.
- Built-in AVAudioUnit effects, such as delay or reverb, may be added only after the dry synth voice works.

Avoid third-party audio dependencies in the first pass. AudioKit is a credible fallback if native oscillator/envelope work starts costing more time than expected, but it should not be the default dependency for the hackathon MVP.

## Controls

The control popover should stay small and useful for live tuning:

- Enable/mute toggle.
- Master volume.
- Movement sensitivity.
- Preset selector, limited to two or three options.
- Accent amount.
- Experimental color mode toggle.
- Lightweight debug readout showing movement intensity and current note.

The readout is part of the hackathon demo surface. It makes tuning easier and helps observers understand what is happening.

## Color Mode

Color mode is a bonus feature, not a dependency for the core demo. Movement remains the instrument; color only modifies it.

If implemented:

- Use ScreenCaptureKit for screen sampling.
- Hue changes timbre.
- Brightness changes filter brightness.
- Saturation changes accent density.
- Missing screen recording permission makes color mode unavailable without breaking movement-only playback.
- If the system requires an app restart after granting permission, show that state in the popover instead of blocking the core instrument.

## Permissions And Failure Modes

Start with cursor polling via `NSEvent.mouseLocation` for the MVP. If this is enough for the local demo, avoid heavier input permissions.

Expected failure behavior:

- If the audio engine cannot start, show the error state in the popover.
- If color sampling permission is unavailable, disable color mode and keep movement-only playback running.
- If performance is rough, lower the sampling frequency before changing the musical model.
- If movement is too jittery, tune smoothing and thresholding in `SoundMapper`.

## Testing And Demo Checklist

Testing should be pragmatic and focused on the code most likely to regress.

Unit-test `SoundMapper` with fake cursor frames:

- Slow movement below the threshold stays silent.
- Fast movement produces non-zero intensity.
- Sharp direction changes trigger accents.
- Accent cooldown prevents repeated rapid triggers.
- Movement stopping fades sound out instead of cutting instantly.

Smoke-test:

- App launches.
- Audio engine starts.
- Menu bar enable and mute controls update playback state.

Manual demo checklist:

- Enable Sounda from the menu bar.
- Move slowly and confirm it stays quiet.
- Move quickly and confirm the lead voice fades in.
- Make sharp turns and confirm accents trigger.
- Change volume and sensitivity live.
- Toggle mute and confirm silence.
- If color mode exists, confirm permission failure degrades cleanly.

## Non-Goals For The Hackathon MVP

- Public distribution, signing, notarization, or installer packaging.
- A full DAW-style interface.
- Recording, exporting, or sharing performances.
- Complex sound design presets.
- Reliance on color sampling for the main demo.
