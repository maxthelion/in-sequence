# QA Surface Review — 2026-06-10

Source: 34 deterministic captures in
`.meta/multipass/runtime/loops/project/observe/qa-surface-coverage/`
(post mixer-livelock fix, build `41ee116` + dirty main attribution work).
Reviewed against the taste profile of the 2026-06-10 bug reports.
Headline findings verified by hand (crops + checksums).

## P0 — looks broken

1. **Transport collapses at default window width (~1216px).** "BPM" renders
   as a vertical B/P/M letter stack, the tempo value is compressed out of
   existence, the Song/Free mode capsules squeeze into unreadable vertical
   pills, and the 1:1:1 position readout stacks vertically. Verified by crop.
   Affects every capture at this width. Fix: `.fixedSize()`/`lineLimit(1)` +
   layout priorities in TransportBar, and a deliberate compact layout below a
   minimum width.
2. **Pervasive truncation on Tracks perform cards** (15/16/17/34): layer
   names render as "NOT…", "RE…", "MUTE SI…"; the "LIVE" badge wraps to
   "LI/VE" on every card. The card layout needs real minimum widths or
   shorter labels — currently the perform surface reads as broken.
3. **Below-the-fold clipping at default window size**: drum part page clips
   the entire step grid (28); kit matrix shows 5 of "6 parts" (29/30); phrase
   page clips the step-order Maps row (32/33); perform layer selector clips
   its third row mid-cell (14); track history buffer clipped (22). Needs
   scrollable containers or tighter vertical budgets.
4. **`unknown unknown unknown unknown` badge** in the top bar on every
   capture — the BuildIdentity badge with no GIT_* values. This comes from
   the in-flight (uncommitted) build-attribution work on main; flagging so
   that work accounts for the all-unknown fallback (hide the badge when
   identity is unknown).
5. **Capture pipeline gap:** 08 and 09 are byte-identical (md5
   `85ad8f96…`) — the `phraseMatrixLayerIndex` visual command does not
   visibly switch the matrix layer (cells still read "Pattern slot"). Either
   the command is a no-op or the matrix ignores layer-index switching;
   diagnose before trusting layer-variant captures. 12 likewise shows no
   open selector.

## P1 — the bug-report classes, still present

6. **Audio input STATE/MONITOR/CHANNEL bubbles are still there** (24/25/26/27)
   — the exact pills the 2026-06-06 input-audio feedback asked to remove,
   duplicating the segmented controls directly beneath them. (Being fixed
   with the input-audio feedback pass.)
7. **Live input monitoring ignores the waveform grammar** (25): two thin L/R
   bars floating in a ~90% empty panel, while recording (26) and loop (27)
   states already render proper waveforms. (Input-audio pass.)
8. **Stock white chrome leaks**: bright white scrollbar tracks on the phrase
   page (32/33) and routing sheet (31); white "Revert" button in the perform
   banner (11); white-filled Slot A header on scenes perform (06); stock blue
   focus rings on play (all) and Cancel (31); white-thumb system sliders for
   pan and crossfade in the mixer (04) where rotaries belong.
9. **Explainer-sentence sweep, round two** (~15 surviving): phrase matrix
   caption (01/08/09/32/33), "plays once, then advances…" + "0 is
   unlimited" (10/13), "Track cards return after a layer…" (14), destination
   captions (18/19/28), "Add one to process the resolved source…" (21),
   "Generator live history…" (22), doubled "No loop assigned" copy (23),
   "Rows follow TrackGroup.memberIDs order." (29/30 — an internal API name
   on screen), step-order sentences (32/33), "Pattern mismatch…" banner
   (29). The Library page (07) is 100% placeholder prose with its rationale
   panel clipped at the window edge.
10. **Redundant status pills**: "SINGLE" + "Pattern slot" repeated in every
    matrix cell (01 ×18); "No default destination" on all 8 perform cards
    (03/11/15/16/17/34); doubled "16-step phrases only" warning (10/13);
    note-repeat interval shown twice per card (17); "EDIT SET None selected"
    chip (03); INHERIT label + "Inherit" caption double-stating (13).
11. **Grid grammar stragglers**: Add Track card shorter than track cards
    (02); Add Scene card taller than scene cards (05); phrase matrix is
    6-wide with floating row actions (01); note-repeat rate pickers are tiny
    chips at card feet instead of full-size cells (17/34); macro cells on
    scenes perform have inner "+ Assign" affordances (06).
12. **Mixer details** (04): Mono 4 strip narrower than siblings with
    "Post fa…" truncation; only 4 of 6 track strips visible with no scroll
    affordance; two identical unlabeled "Add FX" buttons in Master FX; pan
    and crossfade are stock sliders.
13. **Routing sheet** (31): raw hex sample IDs as user-facing labels
    ("Sample B63D8DFA"), stock Cancel/Apply buttons, bottom row clipped.
14. **Bare ✕ buttons** not using the circled standard: perform layer
    selector (14), clip card remove (18/28).

## Suggested order

1. Transport responsive collapse (P0.1) — small, fixes every screen.
2. Perform card truncation + per-card caption removal (P0.2, P1.10).
3. Clipping sweep (P0.3) — scroll containers on track/kit/phrase pages.
4. Input-audio feedback pass (P1.6/7) — in progress.
5. White chrome leaks (P1.8) — scrollbars, sliders→rotaries, focus rings.
6. Explainer + pill sweep (P1.9/10), grid stragglers (P1.11), mixer/routing
   details (P1.12/13), circled ✕ (P1.14).
7. Diagnose the layer-index visual command (P0.5) so QA captures cover
   layer variants truthfully.

## Status update (end of 2026-06-10 session)

- P0.1 transport collapse: ✅ fixed (7c6f4d0) — compression-proof transport.
- P0.2 perform-card truncation: ✅ fixed — compact layer labels, no wrap,
  per-card captions deleted, readable interval chips.
- P0.3 clipping: ✅ kit matrix parts now scroll; perform layer selector and
  track-page clipping remain to verify in captures.
- P0.4 unknown badge: ✅ hidden when identity is all-unknown (fix applied in
  the main checkout's in-flight StudioTopBar work).
- P0.5 layer-index capture no-op: ⏳ still open (QA pipeline diagnosis).
- P1.6/7 audio input: ✅ full rework merged (bubbles gone, waveform monitor,
  arm clarity, record length, quantize, mic permission, generic channel
  selection — channel map needs hardware check).
- P1.8 chrome leaks: ✅ scrollbars, Revert button, Slot A header, routing
  sheet on StudioModal. Mixer pan sliders already rotaries (6da7054).
- P1.10/11 partial: perform-card pills done; phrase-matrix cell pills,
  Library page prose, and remaining explainers still open.
- Mixer review: ✅ all five sections done (6da7054).
- Kit matrix rework + kits/templates model: ✅ spec'd as roadmap item 27
  (`docs/roadmap/drum-kits-and-templates/spec.md`) — feature-sized build,
  not part of this fix pass.
