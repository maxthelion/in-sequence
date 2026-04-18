---
title: "PhatController"
category: "architecture"
tags: [midi, sequencer, typescript, web-midi, controller]
summary: Browser-based MIDI step sequencer and parameter automation controller — sibling project to the Phat iOS AUv3 app, delivering MIDI via the Web MIDI API.
last-modified-by: user
---

## Overview

PhatController (`/Users/maxwilliams/dev/phatcontroller`) is a vanilla-TypeScript web app that acts as a step sequencer and parameter-automation controller over MIDI. It is designed to drive external hardware or iOS targets — notionally including the sibling [[phat]] AUv3 MIDI processor — though nothing in the code hard-codes a specific destination.

## Tech Stack

- **Language**: TypeScript (ES2016+ modules)
- **UI**: Vanilla DOM — no framework
- **Runtime**: Browser, via Web MIDI API
- **Build output**: `public/dest/main.js`
- **Dev server**: `http-server` (port 8080)
- **Persistence**: `localStorage`, keyed by `songId`

## Entry Points

- `src/main.ts` — boots a `Tracker` on `DOMContentLoaded`
- `public/index.html` — loads the compiled module
- `sequencer.js` at the repo root is a `Hello World` stub; the real sequencer lives in `src/lib/sequnecer.ts` (sic)

## Core Model

The state is a 3-axis matrix: **tracks × phrases × parameter layers**.

- **Tracker** (`src/lib/tracker.ts`) — top-level state; owns tracks, phrases, cell matrix, persistence
- **Sequencer** (`src/lib/sequnecer.ts`) — transport/playback at 16 steps per bar, BPM 120, auto-advances phrases
- **Track** (`src/lib/track.ts`) — up to 8 parameter slots per track, backed by `TrackParameter` or `EmptyParameter`
- **Phrase** — reusable 8-bar pattern; holds automation data per track × layer
- **Parameter** (`src/lib/parameter.ts`) — base / `TrackParameter` / `EmptyParameter`; emits MIDI bytes
- **ParameterTemplate** (`src/lib/parametertemplate.ts`) — CC, Note-toggle, or PC templates that generate the MIDI payload

### Key shapes

- `TrackData` — `{ name, midiChannel, parameterIndex[] }`
- `PhraseData` — `{ bars, trackPartGroup[] }` (one per track, 8 layers deep)
- `TrackPartType` — `{ phraseEvents[], phraseMode }` where mode is `0=Single | 1=Bars | 2=Ramping`
- `PhraseEvent` — `{ step, value: 0–127, midiData[] }`

## UI

- `ui/transport.ts` — play/stop, position display
- `ui/paramswitcher.ts` — rotates the visible parameter layer (0–7)
- `ui/phraserow.ts` — per-phrase row rendering
- `ui/modals/` — `TrackModal`, `CellModal`, `NewParamModal` for parameter creation
- `keyhandler.ts` — keyboard shortcuts

## MIDI Output

Parameters encode as one of:
- `cc` — Control Change
- `note` — Note On / Note Off (toggle)
- `pc` — Program Change

Defaults are Mute (NoteToggle), Volume (CC), Program (PC). The Web MIDI API integration is scaffolded via these templates; the codegen is in place even where the device binding is not yet wired end-to-end.

## Relation to Phat

No direct import or runtime coupling to the [[phat]] iOS AUv3 project. The naming suggests intent to drive Phat as a MIDI target, but PhatController emits generic MIDI and will work against any sink the browser can reach via Web MIDI.

## Distinctive Patterns

- 3-axis state (tracks × phrases × layers) rather than a flat step grid
- Phrase composition modes (Single / Bars / Ramping) adapt per parameter type — toggles vs. continuous
- No Web Audio — sound generation is entirely external
- All state lives in `localStorage`; no backend
