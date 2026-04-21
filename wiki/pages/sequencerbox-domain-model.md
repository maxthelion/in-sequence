---
title: "Sequencerbox Domain Model"
category: "architecture"
tags: [sequencerbox, domain-model, reference, step-sequencer, web-audio]
summary: "Overview of the core (non-UI) domain classes in the reference project sequencerbox — Song, Pattern, Scene, Track, Clip, Trigger, Sound — and how they compose into a browser-based step sequencer."
last-modified-by: user
---

## Why this page

`sequencer-ai` is building on top of (or evolving from) the existing `sequencerbox` project at `../sequencerbox/`. This page summarises the underlying class model in sequencerbox so that future decisions in sequencer-ai can either reuse, reshape, or deliberately diverge from it. Focus is on the domain layer (`src/lib/song-elements/`, `src/lib/sounds/`, `src/lib/midi_plugins/`). UI code (`src/lib/ui/`) is intentionally out of scope.

## The hierarchy at a glance

```
Song                                        (top-level container, persisted)
├── clips[]          — global pool, indexed
├── sounds[]         — global pool, indexed
├── samplePool       — decoded AudioBuffers
├── mixer            — Web Audio graph
└── patterns[]
    └── Pattern      (song section, e.g. "Verse")
        └── scenes[]
            └── Scene (snapshot of 8-track state)
                └── tracks[8]
                    └── Track                (one channel)
                        ├── sound → Sound    (ref into song.sounds)
                        ├── stepMachines[]   (arp / generators)
                        └── stepDataManager
                            └── BarData[]
                                ├── triggerClip → Clip  (ref into song.clips)
                                └── fillClip?  → Clip   (optional)

Clip (16 steps)
└── Trigger[16]
    └── NoteDataInterface[]   { pitch, velocity?, duration? }
```

Notable: `clips[]` and `sounds[]` live on `Song` as flat pools. Scenes and bars refer to them by index, not by ownership. This keeps the serialized song compact and lets the same clip be reused across scenes/bars.

## Song (`src/lib/song-elements/song.ts:14-220`)

The root object. Holds global state and Web Audio plumbing.

Key fields:
- `clips: Clip[]`, `sounds: SoundInterface[]`, `patterns: Pattern[]`
- `samplePool: SamplePool` — caches decoded `AudioBuffer`s keyed by path
- `audioContext: AudioContext`, `mixer: Mixer`
- `bpm: number` (default 120), `numTracks: number` (fixed at 8)
- `scale` — from the `chorus` library

Persistence: `save()` / `load()` / `reload()` serialise `rawSongData` (`RawSongInterface`, lines 259-370) to `localStorage` under the key `"song"`. Everything is plain JSON; no binary state.

`Mixer` (nested, lines 222-257) is a small Web Audio graph: per-track `GainNode` → lowpass `BiquadFilterNode` → master gain → `destination`.

## Pattern → Scene → Track

**Pattern** (`pattern.ts:9-108`) — a song section. Fields: `index`, `patternLength` (default 64 steps), `scenes: SceneRawInterface[]`, `stepOrder` (e.g. `"forward"`). Can duplicate itself and its scenes.

**Scene** (`scene.ts:5-43`) — a snapshot of all 8 tracks at a moment in a pattern. Scene-level clip duplication is how you get variations within a pattern.

**Track** (`tracks/track.ts:15-183`) — one instrument channel (0-7). Composes several things:
- `sound` — `SampleSound | ToneSound | PolySynthSound | MultiSampleSound` (reference into `song.sounds` via `soundIndex`)
- `stepMachines: StepMachineInterface[]` — see [[step-machines]]
- `stepDataManager: StepDataManager` — owns the bar grid
- `clip: Clip`, `trackClip: TrackClip` — currently-playing binding
- `volume`, `muted`, `midioutport`, `midioutchannel`
- `dataSet: TrackDataSet` — property descriptors + change tracking

Playhead computation: `track.getPlayHead(step)` applies the pattern's `stepOrder` so tracks can march forward, reverse, or follow custom orders.

## Clips (`src/lib/song-elements/clips/`)

A **Clip** is a 16-step mono- or poly-phonic note sequence — the fundamental unit of sequenced content.

`Clip` (abstract, `clip.ts:10-175`) fields:
- `stepTriggers: Trigger[16]` — user-entered notes (sparse)
- `generatedStepTriggers: Trigger[16]` — notes produced by step machines (see below)
- `stepPlugin: StepMachineInterface` — the generator active on this clip
- `currentTrack: Track` — owning track, for generator context

Key methods: `toggleNoteAtStep(step, note)` (overridden per subclass), `triggersAtStep(i)` (returns user trigger, falls back to generated), `addGeneratedNotes()`, `randomizeFromGenerator()`, `duplicate()`, `clear()`.

Subclasses:
- **MonoClip** (`monoclip.ts`) — one note per step; toggling replaces the note.
- **PolyClip** (`polyclip.ts`) — chords allowed; toggling adds/removes pitches via `Trigger.addPitch()`.

**TrackClip** (`track_clip.ts`) is a tiny binding: `{ clip, track, trackIndex }`. It exists so playback and step machines have the track context a bare Clip lacks.

## Triggers and Notes

**Trigger** (`trigger.ts:3-46`) — a moment in time at step 0-15 with zero or more notes.

```ts
interface NoteDataInterface {
  pitch: number;       // MIDI or scale interval
  velocity?: number;   // 0-127, default 100
  duration?: number;   // length multiplier
}
```

`Trigger.addPitch(note)` is toggle-style (add if absent, remove if present). `Trigger.pitches()` returns raw pitch numbers for quick playback decisions.

## Bars and the step grid

A Clip is always 16 steps, but a pattern can be multiple bars long. **StepDataManager** (`stepdatamanager.ts:5-61`) handles this.

- Each track has a `StepDataManager` holding an array of `BarData`.
- `BarData` wraps `{ triggerClip, fillClip? }` — each bar points at a clip (required) and optionally a fill clip (switched in when "fill" is toggled).
- `getBarIndexForPatternStep(patternStep)` resolves absolute step → bar.
- `getTriggerAtStep(step, patternStep)` resolves absolute step → trigger at the right bar and clip.

This is how a long pattern is built out of 16-step clip chunks without duplicating data.

## Sounds (`src/lib/sounds/`)

All sound sources implement `SoundInterface` — `play(pitch, params)`, `stop()`, `noteEnd()`, `livePlay()`, `type`.

- **BaseSound** (`base_sound.ts:6-69`) — abstract; declares types `"sample" | "synth" | "polysynth" | "multisample" | "clip"`.
- **SampleSound** (`sample_sound.ts:6-137`) — single-file sample with `path`, `start`, `sampleLength`, `pitch` (semitone transpose), `direction` (forward / reverse). Plays via `AudioBufferSourceNode`; buffer fetched from `SamplePool`.
- **ToneSound** (`tone_sound.ts:5-52`) — Tone.js `MonoSynth` wrapper; `play()` → `triggerAttackRelease`.
- **PolySynthSound** — Tone.js `PolySynth` equivalent.
- **MultiSampleSound** (`multisamplesound.ts:6-33`) — pitch-keyed map of `SampleSound`s (e.g. piano samples per note).
- **SoundFactory** (`sound_factory.ts:10-27`) — constructs the right subclass from `params.type`.

`SamplePool` caches decoded `AudioBuffer`s by path — loading is on-demand.

## Step machines (`src/lib/midi_plugins/`)

Pluggable generators/transformers attached to a track. The interface (`basestepmachine.ts:5-68`):

```ts
interface StepMachineInterface {
  type: string;
  init(params): void;
  generatedNotes(trigger: Trigger): Trigger[];
  get(property): any;
  set(property, value): void;
  rawData(): any;
}
```

Typical use: an arpeggiator takes a single input trigger and expands it into multiple output triggers across subsequent steps. Clip stores these results in `generatedStepTriggers` so they can be visualised or frozen.

Related but distinct: **StepFunctions** (`step_generators/stepfunctions.ts`) — step-pattern generators (`RandomStepFunction`, `ClipStepFunction`, etc.) used when randomising clips.

## Playback: Sequence and Loop

**Sequence** (`sequence.ts:7-281`) is the transport + state machine: `playing`, `recording`, `currentStep`, `patternStep`, `absoluteStep`, `fill`, `repeatStep`, `focusBarIndex`, `previewClip`. Exposes `play()` / `stop()` / `togglePlay()` / `startRecording()` / `playNote()` / `toggleBeatRepeat()` etc.

**Loop** (`loop.ts:6-67`) is the scheduler. It uses `window.setInterval(scheduleNotes, stepLengthMilli())` — i.e. **timer-driven, not Web-Audio-scheduled**. Each tick:

1. Advance `sequence.progress()`.
2. For each of the 8 tracks in the current scene:
   - Resolve playhead via `track.getPlayHead(currentStep)`.
   - Fetch the bar → trigger clip (or fill clip, if active) → trigger at step.
   - If unmuted, call `track.sound.play(trigger.notes[0].pitch, soundParams)`.
   - If `midioutchannel` is set, emit MIDI via `MidiScheduler`.

This is simple and predictable but has known jitter issues versus `AudioContext.currentTime`-based lookahead scheduling — see [[playback-scheduling-rethink]] (to be written).

**MidiScheduler** (`utilities/midi_scheduler.ts:4-79`) wraps Web MIDI output and tracks note-off timing.

## Persistence

`RawSongInterface` is the JSON-serialisable shape (`song.ts:259-370`). It contains:
- `name`, `scale`
- `currentPatternIndex`, `currentSceneIndex`, `currentTrackIndex`
- `clips[]`, `sounds[]`, `patterns[]`, `samplePool[]`

Clips and sounds are referenced from patterns/scenes/bars by **index**, not by inline copy. This is the main reason the serialised song stays small.

Default bundled song: `src/lib/songs/song3.js`.

## Cross-cutting patterns

- **Property tracking via `DataSet` / `ObjectWithDataSet`** (`utilities/dataset.ts`, `utilities/objectwithdataset.ts`) — used by Track, Pattern, BaseSound, BaseStepMachine. Declares descriptors (min/max/step/values) for UI binding, validation, and change events. See [[dataset-pattern]] (to be written).
- **Factories** — `SoundFactory`, `StepMachineFactory` instantiate subclasses by `params.type`. Keeps JSON deserialization centralised.
- **Flat pools + index references** — Clips, Sounds, Samples are stored once and referenced from multiple places.
- **Mono/Poly split via subclassing** — `Clip` is abstract; `MonoClip` / `PolyClip` override `toggleNoteAtStep`.

## sequencer-ai vocabulary additions

Types introduced in sequencer-ai that extend or replace sequencerbox concepts:

- **AudioFileRef** — how a destination references a sample on disk: `.appSupportLibrary(relativePath:)` today; `.projectPackage(filename:)` reserved for the future project-pool plan.
- **AudioSample** — library entry for one sample file: stable UUID, name, `AudioFileRef`, `AudioSampleCategory`, optional duration. Not persisted.
- **AudioSampleCategory** — the set of drum-voice tags (kick, snare, hatClosed, …) plus non-drum catch-alls. Bridges `VoiceTag` → category.
- **AudioSampleLibrary** — process-global `@Observable` singleton holding the library scanned from Application Support. Source of truth for `Destination.sample` resolution.
- **SamplerSettings** — per-destination sampler knobs (gain UI-exposed; transpose/attack/release reserved).

## Things worth revisiting for sequencer-ai

Out of scope for this overview but worth separate pages later:

- Timer-based scheduling vs Web Audio lookahead (see [[playback-scheduling-rethink]]).
- Fixed 8-track limit in `Song.numTracks` — hard-coded in several places.
- 16-step clip length — hard-coded in `Trigger[16]` arrays.
- The `currentTrack` reference on `Clip` couples clip data to playback context, which complicates reuse.
- `localStorage`-only persistence — no file export, no versioning.

## References

- Top-level: `sequencerbox/src/lib/song-elements/song.ts`
- Arrangement: `sequencerbox/src/lib/song-elements/{pattern,scene,track_clip}.ts`, `tracks/track.ts`
- Clips: `sequencerbox/src/lib/song-elements/clips/{clip,monoclip,polyclip}.ts`
- Sounds: `sequencerbox/src/lib/sounds/`
- Playback: `sequencerbox/src/lib/song-elements/{sequence,loop}.ts`, `utilities/midi_scheduler.ts`
- Step machines: `sequencerbox/src/lib/midi_plugins/basestepmachine.ts`
