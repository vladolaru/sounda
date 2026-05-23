# Bowed Violin Tuning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use $subagent-driven-development (recommended) or $executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tune `Violin lead` from a violin-ish oscillator into a more convincing bowed lead.

**Architecture:** Keep the existing violin preset and renderer branch, but add bow-specific render state: note/rebow age, delayed vibrato, bow noise transient, and simple body resonances. Avoid samples and keep groove latching.

**Tech Stack:** Swift, SwiftPM, AVFoundation source node, deterministic diagnostics.

---

### Task 1: Diagnostics

**Files:**
- Modify: `Sources/SoundaApp/DiagnosticsRunner.swift`
- Modify: `Sources/SoundaApp/AudioEngineController.swift`

- [x] Add/adjust self-test diagnostics so violin has a distinct bow transient and remains finite/non-clipping.
- [x] Implement bowed attack, delayed vibrato, bow scrape, and body resonance in the violin renderer.
- [x] Verify with `swift build`, `swift run SoundaCoreSmokeTests`, `swift test`, and `swift run SoundaApp --self-test`.
