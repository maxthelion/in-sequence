# Mixer UX Review — 2026-06-10

**Status (2026-06-11): RESOLVED on `feature/mixer-overhaul`**, with one
owner override. The shared `StudioMixerStrip` scaffold (§1) now carries all
four strip kinds including the master column; widths converged on one strip
token + master token (§3); the master is a layout sibling, sends sit beside
it, and the strip row scrolls with indicators (§4); levels converged on dB
and every strip has live meter lanes (§2, roadmap 29); caption/pill sweep
and Add-FX dedup landed earlier (§5). **Override:** pan is NOT a rotary —
the owner's 2026-06-11 ruling
(`20260611-143027-the-mixer-layout-is-a-big-mess-there-are/note.md`) makes
pan a side-to-side element below the fader (`StudioSlideControl`); the
crossfader and pan now share that app-styled slider, replacing the stock
thumbs. Visual QA capture pending. Details:
`20260611-143027-the-mixer-layout-is-a-big-mess-there-are/resolution.md`.

Evidence: QA capture 04-mixer.png (1168×848) + strip implementations
(MixerView.MixerChannelStrip, MixerWorkspaceView.sendReturnStrip,
MixerBusStrip, MasterOutputColumnView).

## 1. The four strip types are four different anatomies

The mixer renders four kinds of vertical column, and the same element sits
in a different place (or differs in size/control type) in each:

| Element | Track strip (200pt) | Send return (190pt) | Bus strip (200pt) | Master (190pt) |
|---|---|---|---|---|
| Name | top, with destination caption | top, after color dot | **bottom**, tappable rename | "MASTER OUT" eyebrow |
| Fader | 36×150, % label below | 32×128, non-interactive "AUTO" | 36×150, % label below | 72×178 meter/fader hybrid, dB scale |
| Pan | 88pt stock slider, right of fader | none | 88pt stock slider | none (crossfader instead) |
| FX/inserts | none | above fader | **above fader (146pt fixed)** | above output |
| Mute/Solo | below sends | none | below fader | none |
| Delete | n/a | n/a | top-right trash | n/a |

Consequences visible in the capture: faders sit at different heights across
adjacent columns, so the most important scan line (all levels at a glance)
zig-zags; the bus name lives at the opposite end of the strip from track
names; insert chains push the bus fader far below the track faders.

**Recommendation:** one `StudioMixerStrip` scaffold with fixed vertical
slots — header (dot+name+context), inserts (fixed-height, collapsible),
fader+pan, actions (mute/solo/edit), footer — every strip type fills or
leaves a slot blank, so identical elements align row-for-row across all
columns. This is the same dedup pattern as StudioModal/StudioOptionButton.

## 2. Same value, different control language

- Pan: horizontal stock slider with white system thumb (tracks, busses).
- Sends A/B: circular knob buttons with % below (tracks).
- Crossfader: stock white-thumb slider (master).
- Level: vertical fader (tracks/busses) vs fader-meter hybrid (master).

The owner's standing direction is rotary knobs for scalar values
(StudioRotaryKnob now exists). Pan as a rotary brings it into one language
with sends, removes the white system thumbs, and (see 3) is the key to
narrow strips. Crossfader is legitimately a slider but should be the
app-styled one, not stock.

- Units disagree: tracks/busses read percent; master reads dB. The
  mixer-main-out intent was "proper decibel meters indicating clipping" —
  level displays should converge on dB.

## 3. Strips are wide because pan sits beside the fader

200pt strip = 36pt fader + 88pt pan slider + 28pt pan label side-by-side.
With pan as a small rotary stacked under or beside the fader and sends as a
2-knob row, a track strip fits ~130–140pt — about +2 visible strips at the
default window. Widths are also inconsistent for no stated reason:
200 (track) / 190 (send return) / 200 (bus) / 190 (master) / 116 (add bus).
One narrow width token for all strips, one for the master.

## 4. Boundary violations (verified in crops)

- **The master column occludes the last track strip.** Master is a ZStack
  overlay (zIndex 1) over the scrolling strips; Mono 4 renders half-hidden
  beneath it ("Post fa…" truncation visible). Strips should end before the
  master column (give the scroll view trailing inset equal to the master
  width) or the overlay needs an opaque edge.
- **Hidden content with no affordance:** 4 of 6 track strips visible;
  Mono 5/6, send returns A/B, and Add Bus are off-screen with
  `showsIndicators: false` — nothing signals scrollability.
- **Master output fader cap renders wider than its lane** (the bulb shape
  over the 30pt meter bars), reading as overflow.
- "Post fader" caption truncates at current strip metrics.

## 5. Smaller consistency items

- Master FX shows two identical stacked "+ Add FX" buttons (empty insert
  slots each render the add affordance) — one add button + clearly inert
  empty-slot placeholders.
- Caption sweep: "Track strips active now", "Post fader", "Wet return /
  Post fader send sum", "After Scene A/B mix".
- "Selected" pill on the selected track strip duplicates the highlight
  border (same class as the phrase-row SEL pill).
- Send-return strips repeat the dead "AUTO" fader — if it's not
  interactive, render it as a meter, not a disabled fader.

## Suggested order

1. Shared strip scaffold with aligned slots (fixes 1 and most of 4's
   truncation by design).
2. Pan → StudioRotaryKnob; narrow width tokens (3, part of 2).
3. Scroll inset for the master overlay + scroll affordance (4).
4. dB convergence + master meter cap fix (2, 4).
5. Caption/pill sweep + Add FX dedup (5).
