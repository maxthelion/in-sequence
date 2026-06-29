# Drum-part Sound tab: rework sound-source selection — disambiguate "no destination" vs "empty sampler", fix the "Load AU…" affordance

**Filed:** 2026-06-29 (owner, verifying the AU-as-drum-part feature)
**Area:** Tracks → kit accordion → part **Sound** tab
  (`Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift`,
   `Sources/UI/SamplerDestinationWidget.swift`)
**Severity:** UX / design rework
**Status:** RESOLVED (2026-06-29)

## Resolution (2026-06-29)

`DrumKitSoundTabRouting` now routes three ways (`panel(forOwnDestination:)`):
own-AU → AU panel, `.none` → a new `expandedSoundChooserPanel`, everything else
(`.sample` incl. missing-sample, `.inheritGroup`) → the sampler panel. The new
chooser is a neutral "No sound source" card offering **Sample** and **AU
instrument** as two equal compact `StudioFXOptionRow` choices — so clearing a
part (X → `.none`) lands here, NOT on the sampler's "Missing sample" card, which
is now reserved for a genuine `.sample` with an unresolved sample. The always-on
verbose "Load AU…" strip under the working sampler was replaced by a compact
bordered "Load AU instrument" button. `.inheritGroup` untouched; filter still
stays dormant-but-stored on swap. New routing test:
`test_soundTabRouting_noneRoutesToChooserNotSampler`.

Follow-up to the AU-as-drum-part work (commits `652f70e6` X-click clear,
`87d412c2` AU panel). The mechanics work, but using it surfaced design problems.

## Problems (from the owner)

1. **"Load AU…" is always present under the sampler**, has too much text
   ("Replace the sampler + filter with an AU instrument."), and **doesn't look
   clickable** (reads as a description, not a button). It's persistent clutter on
   every sampler part.
2. **Clicking the X clears to an "empty sampler", not "no destination".** The
   cleared state shows the sampler's **"Missing sample — Sample … is not in the
   library / Replace with first available sample"** card.
3. **Two different concepts are conflated:**
   - **a sampler that has no/*missing* sample** (a broken/recoverable sampler), and
   - **no sound destination at all** (`.none`).
   They currently render the SAME way, which is confusing.

See image-1 (cleared → "Missing sample" empty-sampler card + Load AU strip) and
image-2 (populated sampler with the Load AU strip pinned underneath).

## Root cause (traced)

- `expandedSoundSamplerPanel` renders `SamplerDestinationWidget` and then ALWAYS
  appends a `StudioOptionButton("Load AU…", detail: "Replace the sampler + filter
  with an AU instrument.")` — hence the persistent, verbose, non-button strip.
- The X clear calls `session.setEditedDestination(.none, for: memberID)`
  (correct at the model level), BUT `.none` is routed to the sampler panel and
  `SamplerDestinationWidget` renders its **orphan/"Missing sample"** card for a
  nil sample. So `.none` (no destination) and `.sample`-with-missing-sample both
  fall through to the same sampler placeholder. There is no distinct "no sound
  source" empty state.

## Desired rework

1. **A single, clear "choose a sound source" model.** When a part has **no
   destination** (`.none`), show a neutral empty state that offers the choices —
   e.g. "Add a sound source" with **Sample** and **AU instrument** options — NOT
   the sampler's missing-sample recovery card.
2. **Reserve the "Missing sample" card for a genuine `.sample` with an
   unresolved/missing sample** (a real recoverable-sampler state) — keep "Replace
   with first available sample" there only.
3. **"Load AU…" becomes a real, compact, clickable affordance**, surfaced as one
   of the source choices (not an always-on descriptive strip under a working
   sampler). Minimal text; looks like a button/menu item. Consider a single
   "sound source" picker (Sample / AU) rather than sampler-by-default + a separate
   Load-AU strip.
4. Keep the existing behaviours intact: filter stays dormant-but-stored on swap to
   AU; X on an AU returns to the chooser; `.inheritGroup` members untouched.

## Acceptance

- `.none` part shows a distinct "no sound source / choose Sample or AU" empty
  state — visibly different from a sampler that lost its sample.
- No always-on verbose "Load AU…" strip under a working sampler; choosing an AU is
  a clear, compact, clickable action.
- Sample-vs-AU selection reads as one coherent "what makes this part's sound"
  choice.

Evidence: image-1-cleared-empty-sampler.png, image-2-sampler-with-load-au-strip.png
