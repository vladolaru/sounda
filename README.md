# Sounda

Sounda is a hackathon macOS menu bar instrument that maps cursor movement to a small synth voice and chime accents.

## Requirements

- macOS
- Swift command-line tools

## Run

```bash
swift run SoundaApp
```

Use the menu bar control to enable or mute Sounda, adjust volume, adjust sensitivity, and quit. The emergency escape hatch is `Control-Option-Command-Q`; `Ctrl-C` from the launching terminal also stops the app.

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
