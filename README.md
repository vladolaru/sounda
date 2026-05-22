# Sounda

Sounda is a hackathon macOS menu bar instrument that maps cursor movement to a small synth voice and chime accents.

## Requirements

- macOS
- Swift command-line tools

## Run

```bash
swift run SoundaApp
```

Sounda starts as a menu bar app. Open the menu bar control to enable or mute playback, adjust volume, tune sensitivity, choose a preset, change accent amount, and quit.

Emergency exits:

- Press `Control-Option-Command-Q` to quit Sounda without using the mouse.
- Press `Ctrl-C` in the launching terminal.

Color mode is intentionally not part of the MVP.

## Diagnostics

Run the deterministic in-process cursor/audio self-test:

```bash
swift run SoundaApp --self-test
```

Expected checks:

- Slow replay reports silence.
- Fast horizontal replay reports non-zero generated audio.
- Sharp-turn replay reports chime/accent activity.

An optional pointer smoke command posts a tiny Core Graphics mouse movement sequence. It is opt-in only and is not part of the core test suite:

```bash
swift run SoundaApp --pointer-smoke
```

If macOS blocks event posting, treat the pointer smoke as a skipped/manual check. The MVP intentionally does not include color mode.

## Demo Checklist

1. Run `swift run SoundaApp`.
2. Open the Sounda menu bar control and confirm audio status is running.
3. Move the cursor slowly; it should stay quiet.
4. Move the cursor quickly; the lead synth should fade in.
5. Make sharp turns; chime accents should trigger.
6. Change volume, sensitivity, accent amount, and preset live.
7. Toggle mute and confirm silence.
8. Quit from the menu bar or press `Control-Option-Command-Q`.

## Development Checks

```bash
swift run SoundaApp --self-test
swift run SoundaCoreSmokeTests
swift test
swift build
```
