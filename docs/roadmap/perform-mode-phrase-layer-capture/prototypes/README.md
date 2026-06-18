# Prototype Summary

## Files

- `01-perform-home-and-phrase-cue.html`: tests transport phrase status, phrase
  cue drawer, and perform-mode task routing.
- `02-layer-bulk-and-matrix.html`: tests the split between batch layer apply and
  layer-perform matrix.
- `03-track-drum-capture-phrase.html`: tests phrase-aware track detail,
  drum-group perform detail, and capture clip/phrase menu.
- `04-phrase-matrix-system-v2.html`: replacement direction that keeps all major
  pages in one matrix-first phrase system: Song, Phrase, Phrase Layers, Phrase
  Scenes, Phrase Cell Edit, and Tracks.
- `05-phrase-value-cell-system-v3.html`: next pass that makes Phrase the local
  container for Overview, Layers, Scenes, and Global Apply, while treating
  Perform as the phrase write mode. Phrase value cells share scope, value, mode,
  and timing grammar.

## Renderable States

- `setPrototypeState("home")`
- `setPrototypeState("cue-open")`
- `setPrototypeState("capture-open")`
- `setPrototypeState("bulk-pattern")`
- `setPrototypeState("bulk-fill")`
- `setPrototypeState("layer-matrix-mute")`
- `setPrototypeState("layer-matrix-pattern")`
- `setPrototypeState("track-detail")`
- `setPrototypeState("drum-group")`
- `setPrototypeState("capture-phrase")`
- `setPrototypeState("song")`
- `setPrototypeState("tracks")`
- `setPrototypeState("phrase-overview")`
- `setPrototypeState("phrase-layers")`
- `setPrototypeState("global-perform")`
- `setPrototypeState("phrase-scenes")`
- `setPrototypeState("phrase-cell")`
- `setPrototypeState("phrase-cue")`
- `setPrototypeState("capture-menu")`

## Scope

The wireframes test information architecture and interaction grouping. They do
not specify production styling, exact copy, or engine storage details.
