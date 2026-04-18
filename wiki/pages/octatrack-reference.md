---
title: "Octatrack MKII Reference"
category: "architecture"
tags: [octatrack, elektron, reference, step-sequencer, sampler, parameter-locks]
summary: Summary of the Octatrack MKII data model and sequencer concepts worth borrowing — parts, trigs, parameter locks, scenes, conditional trigs, and the arranger.
last-modified-by: user
---

## Why this page

The Octatrack is one of three reference devices informing [[sequencerbox-domain-model]] and the unified sequencer-ai design (others: [[cirklon-reference]], [[polyend-play-reference]]). This page captures the *concepts* — not the button combinations — and flags what's distinctive enough to steal. Sourced from the MKII manual §4, §10–§14.

## Hierarchy

```
Set                      (audio pool + many projects; on CF card)
└── Project              (16 banks, 8 arrangements, BPM, sample slots)
    ├── Flex sample slots (128, RAM-loaded)
    ├── Static sample slots (128, CF-streamed)
    └── Bank (×16)
        ├── Pattern (×16)       — trigs, locks, lengths, time sigs
        └── Part (×4)           — machines, sample assignments, FX, track params, 16 scenes
```

A **pattern is linked to a part**. A pattern *does not own* its machine/sample/FX setup — the part does. Multiple patterns can share a part, or each can use a different part within the bank. This separation is the key Octatrack idea.

## Tracks and Machines

8 audio tracks + 8 MIDI tracks. Each audio track hosts a **machine**:

- **Flex** — RAM-loaded sample player; the fast, modulatable option
- **Static** — CF-streamed long sample; up to 2 GB each
- **Thru** — routes the audio inputs
- **Neighbor** — takes the previous track's output (for FX chains)
- **Pickup** — looper
- **Master** — only on track 8, if enabled

Each track has 5 parameter pages (SRC, AMP, LFO, FX1, FX2), each split into MAIN (parameter-lockable, scene-lockable, LFO-modulatable) and SETUP (not). 3 per-track LFOs with an **LFO designer** (16-step custom waveform — effectively a mini-sequencer).

## Trig types

Every step can be one of:

- **Sample trig** — plays the machine
- **Note trig** (MIDI tracks)
- **Lock trig** — carries parameter locks but does not trigger the machine/LFOs/envelopes
- **Trigless trig** — like lock trig but *does* trigger LFOs and FX envelopes
- **One-shot trig** — fires once, auto-disarms; arm/re-arm globally or per track
- **Swing trig** — marks steps that get swing
- **Slide trig** — makes parameter values slide to the next trig's values
- **Recorder trig** — starts the track recorder

## Parameter locks (p-locks)

Per-step parameter overrides on any MAIN-page parameter. Apply to sample/lock/trigless/one-shot trigs. Sliding between two trigs is possible when a slide trig is set. **Sample locks** are a special p-lock that swaps the *sample itself* per trig.

## Scenes and crossfader

Each part holds **16 scenes**. A scene is a set of scene-locked parameter values. Two scene slots (A, B) are bound to the physical **crossfader**, which interpolates between the locked parameter sets. Scene locks override p-locks during fader movement. Special X-prefix parameters (`XVOL`, `XDIR`, `XLV`) exist only under scene-lock to do equal-power fades.

## Conditional trigs

Per-trig `TRIG CONDITION` parameter lock:

- `FILL` / `FILL` (negated) — active only in FILL mode
- `PRE` / `PRE` — true if the previous conditional on this track was true (chains)
- `NEI` / `NEI` — condition of the neighbor track's last conditional
- `1ST` / `1ST` — first pattern cycle only
- `X%` — probability
- `A:B` — true on cycle A of every B pattern cycles

FILL mode is a toggleable global state (momentary, latched, or one-cycle).

## Scale (length & tempo)

Two modes per pattern:

- **NORMAL** — one length + tempo multiplier for all tracks (max 64 steps / 4 pages)
- **PER TRACK** — each track has its own length and tempo multiplier; **MASTER LENGTH** sets the pattern loop-around point (or `INF`). This enables polyrhythm.

Tempo multipliers: `1/8, 1/4, 1/2, 3/4, 1, 3/2, 2`. `2x` effectively doubles resolution to 32nds.

Micro-timing grid is 1/384 per step, per trig. Conditional locks share the `TRIG CONDITION` slot on this screen.

## Arranger

8 arrangements per project, each up to 256 rows. Per-row settings: pattern, repeats, offset (pattern start step), length override, scene A, scene B, MIDI transpose, BPM, mute mask. Special rows: `HALT`, `LOOP` (finite or infinite, nestable), `JUMP`, `REM` (comment). Arrangements can chain to each other.

## What's distinctive / borrowable

- **Pattern ↔ Part decoupling.** Letting sound/machine setup live in a reusable layer separate from the note grid is the single strongest Octatrack idea. Sequencerbox currently couples these via `Track` + `Clip`.
- **Trig taxonomy.** Trigless / lock / one-shot / swing / slide as first-class step kinds — not all just "notes with flags."
- **Conditional trigs with `PRE`/`NEI` chaining.** A tiny logic language on the grid. Cheap to implement; hugely expressive.
- **Scene-crossfader morphing.** Physical (or virtual) fader interpolating two parameter snapshots is more musical than scene-step jumps.
- **Arranger with HALT/LOOP/JUMP/REM.** Programmable song structure; closer to a macro language than a pattern chain.
- **Per-track length + tempo multiplier.** Poly-meter without separate tracks per ratio.
- **Sample locks.** Per-step sample swap decouples the instrument from the note.
