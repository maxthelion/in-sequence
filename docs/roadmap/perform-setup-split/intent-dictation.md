# Perform/Setup split and performability ideas (dictated)

> STATUS: exploration only — NOT scheduled, NOT in the roadmap index.
> Do not build from this document.

Transcribed from Max's dictation 2026-06-12 by the foreman; structure
added, wording preserved where possible. Dictation-decode guesses are
marked [?]. Max: correct anything misheard before this is processed
into the roadmap.

## 1. Setup vs Perform as a global workflow split

Make "perform" more of a global option. The workflow divides into:

- **Setup** — getting your tracks together: instruments, assigning
  which parameters are part of the macros, autoslice configuration,
  routing — all the assembly work.
- **Perform** — a lot of the other stuff goes away so it becomes
  easier to tweak things: toggle fill on/off, switch pattern, mute
  different parts of a drum track. Configuring a thing and playing it
  are different jobs.

## 2. Quantised perform changes

A quantise [? dictated "Qantas"] option in track perform mode: when
you change a value that is a toggle, it doesn't take effect until the
next bar boundary.

## 3. Capture edits (phrase capture)

While performing, get a preview of which values have been changed as
you go along. A "Capture edits" button at the top opens a small mode
asking: stick the edits onto one of the existing phrases, or create a
new one. Maybe a 4x4 matrix so it's really quick to save, and you can
reuse it later.

## 4. Global macros

Macros could be promoted to a global level so you can perform with
your favourites.

## 5. Audio-in track rework

The audio-in track is clunky in its current form. It needs PATTERNS,
where the buffer that's playing — or whether it's live — is a feature
of the pattern it's in. Switching patterns switches between those
modes. That might also be something done in perform mode.

## 6. Drum tracks: kit view first

Less value in the individual per-part generator/step editing [?
garbled in dictation]; default into the drum kit view instead — by
default you want to see all of the parts together, with an option to
dive into one of the parts for greater flexibility. Add a perform
facet for an individual drum kit where you can turn elements on and
off. When a drum kit is on the track perform screen it should be all
the same colour.

## 7. Slicer rework

The slice track is also clunky. Autoslice becomes part of SETUP and
diminishes in prominence in perform mode, which instead gets more
macro-level controls about how the slices are moved around. Maybe the
drum-kit step-sequencer view belongs here — splitting the individual
slices into their own lanes [? dictated "instead of death"].

## 8. Track UI streamline: destination as a tab

The destination panel on the right rarely changes and takes up a lot
of space. It might be a tab like the others (SOURCE / MODIFIER /
HISTORY / DESTINATION).

## 9. Perform overview page

An overview page in perform mode that has all the macros, fill
on/off, track note repeat etc — one place to play the whole project
from.

## 7a. Slicer interface correction (Max, follow-up)

The slicer will have a single slice per lane in the step editor by
default — a diagonal line. That might make kit-style lanes the wrong
interface: too much vertical space for the identity mapping.

(Wireframe §6 revised accordingly: single slice-sequence row —
position = step, value = which slice; deviations from the diagonal
render solid. Structurally a step-order map applied to slices.)

## 7b. Slicer: the three-process tension (Max, follow-up)

There's tension in how slicer tracks work — multiple processes share
one surface:
1. Load the sample in, slice it, apply slices to steps.
2. Select SLICES and change their sound/playback characteristics.
3. Rearrange the order manually — e.g. copying steps around.

(Analysis: these are palette creation / part editing / sequence
editing — the drum-kit decomposition. Slice = part with sound
defaults; step = sequence position with optional overrides
(Rytm sound-lock model). The unresolved design point is SELECTION
SCOPE on the sequence row: a cell tap must be unambiguous between
"this step" and "this slice" — needs an explicit affordance for each
exit. See rytm-study.md §9 and wireframes §6.)

## 10. The per-step "Sound" (drum kits AND slices)

For both drum kits and slices there needs to be a way of opening the
"sound" for each step — which is probably the sample player plus any
FX. One openable Sound object per part/slice.

## 11. Tracks page: audio routing tab

Another tab on the tracks page: AUDIO ROUTING — showing FX (and
allowing macroable params) and destination (master, or a bus etc.).

(Note: this refines §8 — the destination tab becomes a ROUTING tab
covering FX chain + destination, with per-param macro-assign.)

---

## Build-out status & intent reconciliation (2026-06-15, intent-drift lens)

This section records how the SHIPPED build-out maps to the dictated
items above, so this doc and the wireframes stop being read as the
live spec where reality has moved on. Foreman authority for "what is
true now" is .foreman/state.md + decisions.log.md.

- §1 Setup/Perform split — SHIPPED (global WorkspaceMode, top-bar pills).
- §2 Quantised perform changes — SHIPPED (QuantisedToggleScheduler;
  mute+fill; Q:BAR/OFF). Open: LATCH bypasses quantise (owner judgment).
- §3 Capture edits — SHIPPED, hosted on the track-card MATRIX (not the
  dashboard) — consistent with the §9 resolution below.
- §6 Kit view first — SHIPPED (drum tracks default to the kit matrix;
  part editor is the dive-in).
- §8/§11 Destination/routing tab — IN PROGRESS as the
  source-well + mixer/FX-well split (bug 20260615-tracks-routing-...),
  held for a disk-blocked gate. Supersedes the simple "destination tab"
  framing of §8.

### DRIFT — §9 Perform overview (RESOLVED DIRECTION CHANGE, 2026-06-15)
The wireframes (§1/§9) and §9 above describe a row-per-track DASHBOARD
("one place to play the whole project from… all the macros") as the
perform-mode tracks surface. Slice 3 built it. Max then RULED the
perform-mode tracks surface is the existing layered TRACK-CARD MATRIX;
the PerformOverviewDashboard is RETIRED (now unreferenced) and macros
"should live somewhere else."
Consequences a future builder MUST know:
- Do NOT build toward the dashboard-as-perform-surface in §1/§9 / the
  wireframes — that direction is retired.
- The §9 goal (a consolidated "play the whole project / all the macros"
  surface) is currently UNMET. Its home is an OPEN decision: repurpose
  the retired PerformOverviewDashboard view for a macro home, or delete
  it (attention ledger item; owner to decide).
- §4 audio-in-patterns-own-source, the full global-macro assignment
  model, and per-part FX chains remain DEFERRED (need spec/prototype).

### §7/§7a/§7b/§10 slicer + Sound panel — NOT YET BUILT
Slice 6b (shared Sound panel §10) and slice 7 (slicer sequence row
§6/§7a/§7b, step-scope only) are queued behind the routing split and
the disk unblock. The §7b selection-scope question (step vs slice on
the sequence row) is still an open design point.
