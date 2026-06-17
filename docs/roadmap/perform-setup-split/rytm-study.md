# Analog Rytm MKII study — kits & performing

Source: official OS 1.72 manual (Jan 2025), kept at
docs/reference/analog-rytm-mkii-manual-os1.72.pdf (13MB, copyrighted —
do not commit). Read: ch.8 (modes), ch.9 (projects), ch.10 (kits,
scenes, performance), ch.11 (sequencer). Mapped against our
perform/setup exploration (intent-dictation.md + wireframes).

## How the Rytm structures it

- **Project** = 128 patterns + 128 kits + songs + a 128-Sound pool.
- **Kit** = 12 track Sounds + FX + levels + retrig + **its scenes and
  performance macros**. Patterns LINK to kits (non-exclusively).
- **Pattern** = trigs, parameter locks, length/scale, mutes, swing —
  and it brings its kit with it.
- Five radio-button modes on dedicated keys: PLAY, MUTE, CHROMATIC,
  SCENE, PERFORMANCE — every mode one-handed (§8.4 "pragmatic
  operation" is an explicit design goal).

## Borrow-worthy mechanics, mapped to our ideas

### 1. Scenes vs performance macros = one mechanism, two semantics
Both are "up to 48 parameter locks assigned to a pad," edited the same
way. A **scene** applies them as FIXED values, one active at a time
(on/off). A **performance macro** applies them as RELATIVE DEPTHS,
modulated continuously by pad pressure, many at once. Same assignment
model; snap vs continuous application.
→ For our global-macro rack (§7) and master-bus A/B scenes: unify on
one assignment model (parameter + depth), expose two application
modes. Don't build two assignment systems.

### 2. QUICK PERF AMOUNT knob = the favourites idea, proven
Hold [QPER], tap which macros you want, release: now ONE hardware knob
drives that selection without entering any mode. Literally our
"perform with your favourites" — selection-then-one-control.

### 3. Performance config is KIT state
Scenes + perf macros are saved IN the kit, traveling with the sound
set across patterns. → our kit perform facet (part on/off) and any
per-kit macros should serialize with the kit, not the phrase.

### 4. Pattern modes = four quantise semantics for switching
SEQUENTIAL (change at pattern end, default) / DIRECT START (now, from
top) / DIRECT JUMP (now, from same position — seamless) / **TEMP JUMP
(play the new pattern ONCE, then auto-return)**. Plus per-pattern CHNG
sets the change horizon.
→ Our §2 quantise design should be a setting with these named
semantics, not a boolean. TEMP JUMP is the standout borrow: a
structured "fill = visit a variation once and come back", composing
with phrases.

### 5. Fill mode has THREE activation gestures
Cue for one pattern cycle ([FUNC]+[FILL] — arms, plays next loop),
momentary (hold), latched (double-press). Same control, three time
shapes. → maps directly onto our MOM/LATCH chips; add "next cycle" as
the third, quantised gesture. Also: FILL is a per-step CONDITION
(trig condition), so one pattern carries its own fill variation —
different model from our fill lanes, worth a comparison prototype.

### 6. Conditional locks (TRC): cheap generative variation
Per-trig conditions: X% probability, FILL/not-FILL, PRE/not-PRE
(chain off the previous condition's result), NEI (neighbor track),
1ST (first loop only), A:B cycles (play 2nd of every 4 loops...).
→ we have chance + generators; a per-step CONDITION layer (esp. A:B
and 1ST) is a small add with large musical payoff on our step grid.

### 7. Mute preselect = atomic group changes
MUTE mode is machine state (not kit/pattern; survives switches).
Holding [FUNC] while tapping pads PRESELECTS mutes; releasing applies
them ALL AT ONCE. → exactly the arm-then-commit grammar our quantised
toggles need; also argues for "commit several armed changes on the
same boundary together".

### 8. Quick save/reload = the inverse of capture-edits
[YES]+key saves kit/pattern/track/song; [NO]+key reloads. The manual
frames it: "create a restore point before a session of live tweaking
that might not turn out the way you want"; RELOAD PATTERN is live
undo. → our capture-edits (§3) keeps the good take; Rytm's reload
discards the bad one. Same dirty-state machinery, two verbs: the
perform overlay should offer CAPTURE and REVERT as siblings (revert
partially exists in the phrase overlay today).

### 9. Sound locks = per-step source swap, proven
Any pool Sound can be locked to any step (per-step instrument swap).
→ validates our audio-in "pattern owns the source" (§4) and suggests
the same for slices: per-step source selection is an established,
playable model.

### 10. The kit-linking confusion (anti-pattern to avoid)
Kits link non-exclusively to patterns; editing a kit silently affects
every pattern using it, and only the ACTIVE kit survives power-off
unless manually saved. The manual warns about this repeatedly —
that's a UX scar. Our document model auto-saves, but the same hazard
exists for shared kits/step-order maps: when an edit will affect N
other phrases, the UI should SAY so at the edit site, not in a manual.

## Smaller notes
- Retrig with per-track settings + velocity fade curves = our
  note-repeat, plus expressive decay — worth a look for the repeat
  layer.
- Tempo nudge ±10% on arrow keys (DJ-style sync) — cheap, performery.
- Track-level quantize (0-127 strength applied to micro-timing) —
  quantise as an AMOUNT, not a switch.
- Pattern-or-project tempo choice — we only have project tempo.
- Per-pattern scale/length per track (ADVANCED scale) ≈ our phrase
  lengths; their INF + CHNG split (loop forever, change-horizon
  separate) is a clean way to think about phrase-loop vs song-advance.
