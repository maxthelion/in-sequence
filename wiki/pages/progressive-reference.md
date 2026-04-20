---
title: "Progressive Reference"
category: "architecture"
tags: [progressive, chord-progressions, voice-leading, reference, chord-generator, chord-stream]
summary: Summary of the Progressive chord-progression prototype — Roman-numeral chord table, per-slot variant cycling, greedy voice-leading search, metadata-rich progression library, and keyboard-driven performance — feeding the sequencer-ai chord layer design.
last-modified-by: user
---

## Why this page

Progressive (`../progressive/`) is the user's existing chord-progression prototype. It is the strongest reference in this wiki for **how to do the chord layer** — progression authoring, chord-quality variation, voice leading, and live performance — and so informs the sequencer-ai design alongside [[glaypen-reference]] (generator side), [[sequencerbox-domain-model]], [[octatrack-reference]], [[cirklon-reference]], and [[polyend-play-reference]]. Directly relevant to [[north-star-design]] sub-spec 4 (chord layer): `chord-generator` source, `chord-context` sink, `chord-stream` type, `quantise-to-chord` consumption modes.

## What Progressive is

A browser (TypeScript / Web MIDI / Tone.js) single-page app. The user picks a root note and a named progression ("vi–IV–I–V"), gets one button per chord slot, plays with the computer keyboard (`arstdhn` for chords, `qwfpgjluy;` for melody), and optionally runs a 16th-note sequencer (chord hold / arp up / down / updown) behind it. Everything is monophonic-voicing — one chord active at a time.

## Shape

```
document-load
  ├── chordprogressions.json     (progression library with metadata)
  ├── chords[]                    (Roman-numeral → PC-offset table)
  └── UI
      ├── progression selector    (select a progression string)
      ├── chord-slots[]           (one per token in the notation)
      │   └── variants[]          (cycled via scroll wheel)
      ├── chord-palette           (I…VII + i…vii; drag onto a slot to replace)
      ├── sequencer controls      (bpm, beats-per-chord, mode)
      └── root-note selector
```

## Chord table

`chords: { position, notes }[]` — 70+ entries keyed by Roman-numeral string, each holding 3–5 **pitch-class offsets from the song root** (0 = root, 4 = major third, etc.). Covers:

- Diatonic triads in major (I…VII) and minor (i…vii)
- Sevenths (I7, V7, ii7, IIm7b5…), sixths, ninths, 7b5, 7#5
- Flat-degree chords (bII, bIII, bVI, bVII…) for modal/modal-mixture progressions

Notes are stored as **pitch classes only** (0…11). Octave assignment is the voicing layer's job. `getNoteOffset(rootNote)` adds `60` (C4) + the root's PC offset, so every voicing sits around middle C before voice-leading shifts it.

## Variant derivation

`getVariants(basePosition)` expands a slot's base chord into 7–8 quality variants on the fly, **built from the base chord's root and third** rather than re-looked-up:

```ts
isMinor = (third - root) mod 12 === 3
major variants: ['', 'maj7', '7', '6', 'add9', 'sus4', 'sus2']
minor variants: ['',  '7', 'maj7', '6', '9', 'add9', 'sus4', 'sus2']
```

Scroll-wheel on a slot cycles through its variants. This is the chord-quality axis, separate from the Roman-numeral axis — "V in this progression, but try it as V7" is one flick. Relevant to sub-spec 4: the chord-generator block wants both axes (degree and quality) as independently addressable parameters.

## Voice leading

`applyVoiceLeading(rawMidi)` is the part worth studying closely.

1. For each note in the new chord, consider the candidate pitches `{n-24, n-12, n, n+12, n+24}`.
2. Enumerate every combination that falls inside `[36, 96]` (C2…C7).
3. Score each combination by `Σ |sortedCandidate[i] - sortedPrevious[i]|` with a 12-semitone penalty per length mismatch.
4. Return the best-scoring voicing; cache it as `lastVoicing` for the next call.

Effect: successive chords share notes where possible, the bass moves smoothly, and the voicing stays in register. Brute-force exponential in chord size — fine for 3–5 note chords, would need a priced search for larger voicings. The sequencer-ai `quantise-to-chord` block (spec §Pipeline layer) needs a voice-leading stage equivalent to this; lift the algorithm directly for MVP and revisit if larger chords surface.

The prototype also changes the slot-button label to show `root/bass` when voice leading puts a non-root in the bass (e.g. `C/E`).

## Chord slots and progressions

Progression notation is a **string**, split on `–` or `-` into tokens (`"vi–IV–I–V"` → `["vi", "IV", "I", "V"]`). Each token becomes a `ChordSlot = { variants, currentIdx }`. Per-slot:

- Scroll cycles variants.
- Drag-drop from the chord palette (PALETTE_CHORDS = I…VII, i…vii) replaces the slot entirely.
- Pointer-down triggers `playSlot` (hold-to-play); pointer-up releases.

Progression = ordered list of slots; the sequencer advances `slotIdx = floor(tick / ticksPerChord) mod progressionLength`. No bar-aware concept beyond "beats per chord". No modulation between slots (global `rootNote` is set once).

## Progression library as metadata

`chordprogressions.json` is hand-curated, ~50 entries. Each record:

```json
{
  "notation": "vi–IV–I–V",
  "songs": ["Creep - Radiohead", "The Night We Met - Lord Huron"],
  "description": "Haunting and emotional, often used to evoke longing or sadness.",
  "common_additions": ["vi7", "IVadd9", "V7"],
  "genres": ["Indie", "Alternative", "Pop"],
  "keywords": ["haunting", "emotional", "longing", "sad"]
}
```

`description`, `genres`, and `keywords` are authored, not derived. This is the kind of payload a sequencer-ai **chord-gen preset** wants (spec §Bundled content, "4 chord-gen presets") — not just the notation, but mood metadata for preset browsing and future tension/brightness-macro mapping.

## Sequencer playback

Tone.js `Loop` at `'16n'` with two modes (`chord` hold / `arp` up-down-updown):

- `ticksPerChord = beatsPerChord * 4` — progression stride in 16th-note ticks.
- **Chord mode:** on the first tick of a slot, release previous voicing, compute new voicing (through voice-leading), attack it, hold until next slot.
- **Arp mode:** compute slot voicing once, then on each tick pick `voicing[stepInChord mod len]` (or reversed, or ping-pong), release the prior note, attack the next.

Per-slot `seqHeldVoicing` / `seqArpVoiced` track what's currently sounding so releases go to the right notes. Identical pattern to what a sequencer-ai `chord-generator` → `note-generator` → `midi-out` chain will need on the render thread (with sample-accurate release scheduling, not Tone.js's lookahead).

## Melody scale derived from chord

`getMelodyScale(chordNotes)` picks a pentatonic scale **keyed to the current chord's quality**:

- major chord → `[0, 2, 4, 7, 9]` major pentatonic
- minor chord → `[0, 3, 5, 7, 10]` minor pentatonic

Spanned across two octaves (10 notes). This is the melody-side of the "chord context informs everything downstream" idea — a drop-in analog for `quantise-to-chord(mode: chord-pool)` in the spec, restricted to a pentatonic subset.

## What's distinctive / borrowable

- **PC-offset chord table keyed by Roman numeral.** Portable, reusable across roots; the song-root is added at voicing time. Direct fit for the `chord-generator` block's internal chord library.
- **Variant derivation from (root, third).** Quality axis expanded on the fly rather than enumerated — adding a new variant suffix adds one row, not 14 rows × numerals.
- **Greedy voice-leading by octave-shift search.** Small algorithm, large musical payoff. Port as the MVP voicing stage of `quantise-to-chord` and `chord-generator`.
- **Progression library with mood metadata.** `description`/`genres`/`keywords` turn preset browsing into a mood-driven activity; maps cleanly to sequencer-ai chord-gen presets.
- **Slot-level variant cycling orthogonal to progression slot.** Two axes (which degree, what quality) controllable independently at performance time. Lift this into `chord-generator` as a per-slot lockable `quality` param.
- **Chord-hold vs arp as a playback mode, not a different block.** Identical source, different downstream consumption — fits the spec's "chord-stream subscribers choose their own consumption mode" rule.

## Gaps (things sequencer-ai would want to add or change)

- **Single song key.** `rootNote` is a global `<input>`; no modulation across slots or phrases. Sequencer-ai's `chord-stream` is `(root, chord-type, scale)` per-step, so per-slot root is free once lifted.
- **Notation is a string.** `"vi–IV–I–V"` is parsed with `split(/[–-]/)` at UI time; no structured progression type. A `Progression` value type with `[ChordSlot]` and per-slot `{ degree, quality, duration, tensionHint? }` is the sequencer-ai shape.
- **No bar/time-signature awareness.** `beatsPerChord` is a flat number; progressions can't have varying slot lengths. Sub-spec 4 should let a slot span N bars (or fractions) and honour the phrase's time signature.
- **Voice-leading search is brute-force.** 5⁴ = 625 candidates for a 4-note chord is fine; 5⁷ for dense voicings is not. Branch-and-bound with early-pruning lifts the ceiling cheaply.
- **No scale context.** Chord tables are diatonic + chromatic borrowed chords, hardcoded. Sequencer-ai's `chord-stream` carries a `scale`; `force-to-scale` downstream should honour it rather than each block having its own scale table.
- **No per-progression persistence of slot edits.** Drag-replacing a slot mutates `activeChordSlots` in memory; reselecting the progression rebuilds from the JSON. An authored-progression path (the spec's `authored-chord-row` source) needs a saved-progression layer separate from the curated library.
- **Monophonic chord at a time.** One voicing on the synth, even in arp mode. The spec's multi-track consumption (bass uses `scale-root`, pad uses `chord-pool`, drums ignore) has no analog here — each subscriber picks its own realization from a single broadcast.

## References

- Chord table + variants + voice leading: `progressive/src/main.ts:11-150`, `820-860`
- Progression library: `progressive/public/chordprogressions.json`
- Sequencer playback (chord + arp): `progressive/src/main.ts:525-626`
- Melody scale from chord quality: `progressive/src/main.ts:167-176`
