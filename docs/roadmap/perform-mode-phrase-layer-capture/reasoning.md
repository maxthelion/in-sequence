# Reasoning

## What The Current Captures Show

The current app already has several ingredients that should be kept:

- transport and primary page navigation are stable at the top;
- Tracks Perform has a useful card matrix, layer selector, basis phrase label,
  edit set, momentary/latch choice, and unsaved-edit banner;
- Phrase has the richer phrase matrix and phrase rows, but it is currently a
  planning/editor surface more than a live perform surface;
- Clip History shows that capture can work as a track-local history surface,
  but the concept is broader than melodic generator history;
- Drum Kit Matrix makes the group visible as rows of parts, which is much
  better than treating kick/snare/hat as unrelated tracks.

The tension is that perform mode now contains too many different mental models:
track cards, phrase matrices, layer selectors, fill preview, clip history, scene
perform, and drum group editing all appear as separate mechanisms. The
wireframes try to collapse these into three repeated ideas:

- playback is always inside a current phrase;
- performance edits happen against a copy/staging area of that phrase;
- capture commits either track output into a pattern slot or phrase-level
  changes into a phrase copy.

## Proposed IA

### Transport Owns Phrase State

The transport should always show the current phrase, because the sequencer is
always playing inside one phrase. Cueing a next phrase belongs next to that
status rather than hidden inside the phrase page. A compact phrase cue drawer
can show:

- current phrase;
- queued phrase;
- immediate switch;
- cycle-end switch;
- phrase length/repeat/loop policy.

This makes "Free" versus "Song" less mysterious: free/performance mode still
has a current phrase, but phrase advance is manual or cued.

### Perform Mode Has Four Jobs

The wireframes split perform navigation around the tasks the user named:

- move between phrases;
- make layer changes across tracks;
- change the sound/state of a running track;
- change scene values and crossfade.

The top-level perform landing is not a marketing page. It is a routing surface:
large enough to orient, but each route lands on a real matrix/editor.

### Layer Bulk Edit Versus Layer Perform

There are two similar but distinct needs:

- bulk apply: select tracks, show all layer options at once, and apply a chosen
  value to every selected track;
- layer perform: choose one active layer and show one control per track so the
  current state is visible across the whole set.

These should not be the same screen. Bulk apply is a batch operation with
selection and confirmation. Layer perform is a playing surface with a single
active layer, immediate or quantized toggles, and scan-friendly cells.

### Track-In-Phrase Detail

The track page should be phrase-aware. If the current phrase mutes the track,
the track page should say that and the track should not sound. If the phrase
selects pattern 7, the pattern row should indicate that as the active phrase
mapping. Fill Preview should become "Fill in Phrase" rather than an external
preview toggle.

For deeper phrase mapping, a track-in-phrase view can expose each layer as:

- mapping mode: single value, per bar, or continuous event;
- values: pattern/mute/fill/repeat/volume/pan etc;
- capture status: live edits that have not yet been printed into the phrase.

This is the likely bridge between perform mode and phrase authoring.

### Drum Groups

Drum groups should be first-class perform objects. A kit has shared phrase
mapping for pattern and clip-like settings in the main case, while parts can
still have part-specific performance states such as mute. That avoids making
kick, snare, and hats feel unrelated, while keeping the escape hatch for part
differences.

The wireframe treats part mute as the first drum-group perform layer. Pattern
sharing is shown as the default, with "mixed" called out as a warning state
rather than the normal path.

### Capture

Capture should move upward from a track-history tab into a transport-level
menu. There are at least two captures:

- Capture Clip: choose a track, then save recent output into a pattern slot on
  that track.
- Capture Phrase: print layer, scene, crossfader, macro, and continuous changes
  into a copy of the current phrase.

The existing Clip History workflow still fits as a destination-specific version
of Capture Clip. The important change is that the user should not need to know
which page owns history before deciding "I heard something, keep that."

## Things Intentionally Deferred

- Cue output preview for auditioning changes.
- Full continuous event editing for phrase automation.
- Detailed scene parameter editing.
- Exact engine storage format for phrase copies and event data.
- Whether drum part mutes belong in the shared kit phrase mapping by default.

## Prototype Checklist

- The prototypes use monochrome structural UI with semantic accent colors.
- Off-path controls are dashed or labelled as stubs.
- Each HTML file is standalone.
- Each important state has a stable `setPrototypeState(...)` function.

