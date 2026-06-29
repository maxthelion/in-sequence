# New-bugs verification checklist (2026-06-29)

Human/TCC-tier checks for the 6 "new" bugs fixed on `audio-routing-cleanup`.
Visual/click items first (no AU), then by-ear (load a real AU, e.g. Analog Lab V).

## Visual / click (no AU needed)

- [ ] **1. Mixer send-strip layout** (`4b9168e5`) — Mixer → Send A/B / FX return
      strips. Insert chip shows full label (no truncated "8…"); toggle+reorder+trash
      row not cramped.
- [ ] **2. Tracks-page kit restructure** (`e1939269`) — Tracks page. Kit is a normal
      grid cell (no green wrapper), expand button on the cell, parts inline as cells
      when expanded. CONFIRM: OK that the kit's "OWN BUS" pill was removed? (one-line
      add-back if not).
- [ ] **3. Button hit-areas** (`6df1321c`) — Click the padding/edge (not the glyph) of
      nav pills, transport mode picker, drum-kit chips → registers.
- [ ] **4. Drum-part X clears the sound** (`652f70e6`) — Expand kit → part Sound tab →
      click X on sampler card → clears to placeholder (was a no-op). Undoable.

## By ear (load a real AU)

- [ ] **5. AU preset picker applies immediately** (`ed12360a`) — Load AU, open preset
      browser, select a preset → patch switches immediately.
  - [ ] Off-by-one: picked patch is exactly the one heard (not N±1)?
  - [ ] Normal-named-preset AUs ("Warm Pad") still switch (no regression)?
  - [ ] Persistence: save + reload → preset sticks? (flagged as a likely gap)
  - [ ] Indicator is a checkmark (not a star).
- [ ] **6. AU as a drum-part sound** (`87d412c2`) — Part Sound tab → "Load AU…" → pick
      AU → AU panel appears (name + Presets + X); part plays through the AU.
  - [ ] Presets load on the part.
  - [ ] X returns to sampler with filter settings intact.
  - [ ] Live sampler↔AU swap while playing: no click / no hung note (the risky leg).

## Machine-verified (no action)
- graphlock-reentry-crash + AU-rescan (`cbc11760`) — regression-tested.
