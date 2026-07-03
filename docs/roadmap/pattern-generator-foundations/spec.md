---
status: accepted
stage: ready-for-build
priority: high
blocked_by: [merge of feature/tab-well-grammar to main]
---

# Pattern & Generator Foundations — builder-facing goal spec

Consolidates every decision from the 2026-07-02/03 design passes into one
buildable batch. Sources of law, in precedence order:

1. This spec.
2. `docs/intents/inbox/20260703-101500-generator-pipeline-synthesis.md`
   (pipeline model, chord semantics, generator vocabulary).
3. `docs/intents/inbox/20260702-1500{01,03,04,05,06,07,08}-*.md` (owner's
   verbatim intents + clarifications; note the PARKED markers).
4. `docs/roadmap/track-view-ia/tab-unification-and-canon-creep.md`
   (D grammar, state-colour vocabulary) + `docs/ux-canon.md`.
5. Prototype ground truth (renders are the spec where prose is ambiguous):
   `11-step-layer-system`, `12-clip-randomize`, `14b-generator-editor-final`
   in `docs/roadmap/track-view-ia/prototypes/`.

## Non-goals (owner-parked — do NOT build, do not "improve into")

- Pattern-row v2 state model (pulsing bullet / right-click override / ghost
  phrase — prototype 15). Fill mode builds against CURRENT row visuals.
- Track-perform transactional session (intent 150009).
- Any change to the stored generator pipeline model: `.mono(trigger:pitch:
  shape:)` STAYS. Editor presentation changes only.
- Octave as a live/perform action (third scope of 150007) — parked with the
  perform work. The other two octave scopes ARE in this batch (WS3, WS4).

## Engine-wide constraints (all workstreams)

- Audio Engine Hard Rules (AGENTS.md); realtime-path / runtime-ownership /
  realtime-rng lints green. ux-canon-lint strict zero (state colours per the
  fenced vocabulary: green=capturing, amber=pending, red=recording-events —
  small solid elements only).
- Precompute/invalidation contract: anything generation-affecting must bump
  `generationInputRevision` (installPlaybackSnapshot / invalidatePreparedTick)
  or be keyed into `BarKey`. The scoped-runtime macro fast path (426c0771) is
  ONLY for dispatch-time values. Model on the chord-context precedent
  (4e0ba807).
- No RNG on the tick path; deterministic per-position hashing where
  "randomness" must be loop-stable (WS5 defines the idiom).
- Tests follow the shutdown-at-teardown convention (bacee620/a414edf9).
- After each workstream lands: run the qa-surface-coverage capture pass so
  the bug-reporter gallery reflects it (add rows for new surfaces).

---

## WS1 — Fill mode becomes real (intent 150001)

Behavior:
- Every clip carries normal + fill step items (existing Lane model). Engaging
  FILL on a track plays the fill items of the current pattern's clip in place
  of normal items, quantized per the existing quantised fill-flag machinery.
- Fill PREVIEW (existing toggle) both displays fill steps in the step grid
  and audibly plays them for the current pattern while active.
- Disengaging returns to normal items at the same boundary discipline.

Acceptance criteria:
- AC1: with fill engaged, the realized note stream for the track equals the
  clip's fill items (offline render test, event-recorder comparison).
- AC2: fill preview ON: step grid shows fill items; engine plays them;
  preview OFF restores normal — verified by an engine test on
  TrackFillPreviewPlaybackSnapshot consumption + a capture row.
- AC3: fill engage/disengage mid-playback commits at the bar boundary, no
  immediate-mode triggers introduced (timing-probe assertion).
- AC4: capture rows added/refreshed: 20-track-fill-preview-active + a new
  fill-engaged row.

## WS2 — Randomize = bake(generator) (intent 150003, synthesis §3)

Behavior:
- One conversion primitive `bake(source, seed) -> clip content` shared by
  randomize and (later) capture-history save.
- Dice button above the pattern selector (prototype 12 placement/grammar):
  press = roll seed, run the clip's randomize generator params, overwrite the
  current clip DESTRUCTIVELY with undo registration.
- Settings sheet (prototype 12): density, scale+root, octave center+span,
  velocity variance, gate variance. Re-roll = new seed + re-bake, audible
  immediately (audition path). Settings + last seed persist on the clip.
- Slots whose clip has persisted randomize settings show the quiet ring
  badge (prototype 12).

Acceptance criteria:
- AC1: bake(params, seed) is deterministic — same seed, same clip bytes
  (unit test).
- AC2: randomize overwrites current clip; one undo restores the previous
  content exactly (session test).
- AC3: settings + seed survive save/reload of the document (codable test).
- AC4: re-roll audibly plays without committing until the sheet closes
  (audition-override path — engine test that the override is active during
  the sheet and cleared after).
- AC5: no RNG on the tick path (bake runs off-tick; realtime-rng-lint).
- AC6: capture row for the settings sheet + rolled state.

## WS3 — Layer system: pitch layer, octave dimension, quick-switch
##        (intents 150006/150007-editing/150008; prototype 11)

Behavior:
- New PITCH layer in the step grid (mono + poly): per-step cell shows scale
  degree as dominant glyph + octave as the 3-dot low/mid/high band with a
  corner badge past +/-2 (prototype 11 cell design). Octave dots are click
  targets (octave editable per step).
- Layer QUICK-SWITCH: the compact matrix switcher (prototype 11) replaces
  the current selector rows on mono AND slicer; closed state is a solid
  value chip showing current layer; open state is the matrix. Inset-track
  value-selector family, never section pills.
- Grid cell grammar unified: binary=solid fill; magnitude=bar-in-outline;
  discrete=solid+glyph (prototype 11's three-type system) across mono and
  slicer layers.

Acceptance criteria:
- AC1: pitch layer edits write through to clip content; generated tracks
  show generator output read-only or bake-prompt (decide with the WS4 result
  strip; document choice).
- AC2: one switcher component serves mono and slicer layer sets (component
  reuse assertion + both capture rows).
- AC3: layer switch latency imperceptible (no snapshot install per switch —
  layer selection is view state, not document state; test that
  generationInputRevision does NOT bump on layer switch).
- AC4: capture rows for pitch layer (mono) + quick-switch open (mono,
  slicer).

## WS4 — Generator editor + vocabulary + identity (intents 150004/150005,
##        synthesis; prototype 14b)

Behavior:
- Editor per prototype 14b: header (mode chip + FOLLOWING chord chip always
  visible + Bake-to-clip dice), always-visible combined RESULT STRIP (one
  bar, resolved triggers with pitch labels), then TRIGGER | PITCH stage
  tabs (inset-track family).
- Trigger stage: EUCLIDEAN | WEIGHTED (new: per-step probability weights) |
  MANUAL; CLUSTER bipolar rotary (repulsion <-> attraction) governing where
  added triggers land.
- Pitch stage: POOL (root+scale, chord filter chip — sidechain filters the
  pitch pool ONLY, never triggers); SELECTION memory-axis rotary
  (uniform <-> last-note, markov styles revealed past center); DEVIATION
  group (accidentals %, octave +/- span, chromatic leading %).
- STABLE GENERATOR IDENTITY: switching mode/kind mutates the pool entry in
  place — same UUID, pattern-bank references survive, shared params (root,
  scale, octave range) carry across modes. No delete+readd.
- Chord generator (150004): conformed surfaces per prototype 14a
  (instrument role + consumer-side FOLLOWING picker), included in captures.

Acceptance criteria:
- AC1: mode switch preserves entry UUID + slot bindings + shared params
  (model test; RED against current delete/readd behavior).
- AC2: chord sidechain affects pitch selection only — a fixture where chord
  changes mid-run: trigger stream byte-identical with/without sidechain,
  pitch stream differs (offline event-recorder test).
- AC3: weighted + cluster produce deterministic streams under fixed seeds
  (precompute equivalence stays green; PrecomputeBarEquivalence extended).
- AC4: deviation controls: accidentals only emits out-of-pool notes when
  factor > 0; octave span bounds register; leading resolves stepwise into a
  pool note (unit tests on the pitch stage evaluator).
- AC5: result strip reflects the realized next bar (same data source as the
  precompute publish — no separate simulation drift; test strip content ==
  precomputed bar).
- AC6: editor fits without scrolling at the standard well height for
  euclidean + markov (visual check via capture row; flag if 14b's layout
  judgment demanded changes).
- AC7: capture rows: generator trigger tab, pitch tab, chord instrument,
  chord consumer.

## WS5 — Density transform + phrase-level density macro (synthesis §4)

Behavior:
- A DENSITY transform stage over any source's note stream: value 0..1 adds
  ghost triggers at candidate positions derived from existing hits,
  respecting the source's CLUSTER character (shared parameter with WS4).
  Deterministic per-position: inclusion = hash(patternID, step, densityValue
  band) — loop-stable, monotonic under sweep (higher density strictly adds).
- Ghost triggers: velocity-scaled from neighbours, pitch from the pitch
  stage's pool policy (or repeat-last for clips).
- Exposed as a phrase-layer macro (phrase-level value, per existing layer
  macro plumbing) and per-track.
- ENGINE: density is generation-affecting. Introduce a
  `generationAffecting` flag on macro descriptors; flagged macros bypass the
  scoped-runtime fast path (426c0771) and ride the revision-bump route.

Acceptance criteria:
- AC1: same (pattern, density) -> identical ghosts every loop (offline
  determinism test).
- AC2: monotonic: ghosts(0.5) is a subset of ghosts(0.7) (property test).
- AC3: cluster=attraction produces adjacent-to-hit ghosts; repulsion
  maximizes spacing (distribution assertions).
- AC4: density change invalidates precomputed bars (revision bump test,
  chord-context pattern); dispatch-only macros still skip installs
  (existing SessionDestinationMacroTests stay green).
- AC5: zero tick-path RNG/alloc regressions (all three realtime lints).
- AC6: capture row: a pattern at density 0 vs 0.6 (two rows).

## WS6 — Selective scene inputs (roadmap 25, owner pulled forward)

Behavior:
- Per-track scene membership: each track (and kit bus) can be assigned to
  scene A, B, or both; MasterBusHost gains a per-track scene-membership gain
  stage so the A/B crossfader morphs only member tracks.
- Routing page UI: a proper scene-slot selector in the D/inset grammar —
  clearly distinct from Send A/B (the conflation removed in 353829be must
  not regress; keep Send A/B knobs untouched).
- Default: all tracks member of both (current behavior preserved).

Acceptance criteria:
- AC1: crossfader at full A silences B-only tracks' contribution and vice
  versa (offline render RMS test per membership combination).
- AC2: membership changes while running are click-free (ramped; Hard Rule 5
  gates: RampBeforeDisconnect family green).
- AC3: Send A/B knob behavior byte-identical before/after (regression test
  on TrackMixSettings paths).
- AC4: old documents (no membership field) decode to both/both (codable
  migration test).
- AC5: capture rows: routing page with selector; scenes view showing
  membership.

---

## Sequencing & isolation

Build order: WS1 -> WS2 -> WS3 -> WS4 -> WS5 -> WS6, sequential per
workstream (shared UI files), each on the merged main, one branch per
workstream (`feat/ws1-fill-mode`, ...), full gate set per landing. WS4's
model changes (stable identity) land BEFORE its editor. WS5 depends on WS4's
cluster parameter. WS6 is independent and may run in parallel with WS1-2 if
worktree/file isolation is maintained (engine/Audio files vs UI files).

Every workstream ends with: capture pass, gallery check note, and an entry
appended to this spec's CHANGELOG section below.

## CHANGELOG

- 2026-07-03: spec created from the 07-02/03 design passes (Claude, owner-
  reviewed decisions throughout).

- 2026-07-03: prototype 14b layout finding folded into WS4/AC6 — the PITCH
  stage overflows a 900px height (Deviation trio below the fold); builder
  must either confirm the well pane scrolls internally (canon Rule 8) or
  tighten Pitch vertical rhythm (Deviation dials in one tight row, drop the
  Selection meta-text column). Result-strip accidental/octave flags are
  legible but subtle — check at real app zoom.

- 2026-07-03: WS3 delivered on `feat/ws3-layer-system` (salvage peel from the
  wip/ws-batch-snapshot batch, rebased onto post-WS2 main). Pitch layer
  (degree glyph + 3-dot octave band + corner badge past +/-2) in the shared
  step-cell grammar; octave band is a per-step click target cycling the
  register in place (prototype 11); one generic `StepLayerQuickSwitch`
  serves mono + slicer (AC2 assertion in UnifiedStepCellTests). AC1
  DECISION: generated tracks are READ-ONLY on the step-layer surface — the
  clip grid (and its write path) only attaches to clip sources, and the
  generator branch shows a visible GENERATED / STEP LAYERS READ-ONLY badge;
  the bake-prompt alternative is deferred to WS4's result strip. AC3: layer
  selection stays view state (harness test pins generationInputRevision +
  store revision unchanged across layer/switcher commands). AC4: capture
  rows 22c/22d/23fa; capture pass pending an attended visual-automation
  session (unattended TCC gate).

- 2026-07-03: WS2 delivered on `feat/ws2-randomize` (salvage peel from the
  wip/ws-batch-snapshot batch, rebased onto post-WS1 main). AC1-AC6 covered
  (ClipContentMacroLaneTests / SessionBatchHelperTests /
  QuantiseHarnessProtocolTests + realtime-rng-lint + rows 20b/20c). Canon
  fix folded in: the persisted-settings slot ring badge now takes the
  surface accent (snapshot used StudioTheme.success; green is fenced to
  capturing). Capture pass for 20b/20c pending an attended visual-automation
  session (unattended TCC gate).

- 2026-07-03: WS5 delivered on `feat/ws5-density` (salvage peel from the
  wip/ws-batch-snapshot batch, re-knit against post-WS4 main). The DENSITY
  transform lives in `GeneratedSourceEvaluator.applyingDensityTransform`:
  inclusion = FNV-1a hash(patternID, step) + a splitmix64 avalanche
  finalizer (the snapshot's hash was step-invariant in the low 24 bits —
  admission collapsed to all-or-nothing per pattern; fixed during the peel)
  compared against the density value — loop-stable, strictly monotonic
  under sweep, zero RNG. Cluster character shared with WS4
  (`GeneratorParams.densityCluster`): attraction admits adjacent-to-hit
  candidates, repulsion far-from-every-hit. Ghost policy COMPLETED beyond
  the snapshot (which had fixed velocity 72 / first-pitch): ghosts are
  velocity-scaled from neighbours (mean of nearest preceding/following hit
  × 0.65) and repeat the nearest preceding hit's pitch — repeat-last for
  clips, a realized pool-policy note for generators
  (`DensitySourceHit` profiles; generator profile = deterministic full
  evaluation under the preview seed). Exposure: the existing built-in
  density phrase layer compiles into a typed per-step buffer
  (`TrackPhrasePlaybackBuffer.density` → `ResolvedTrackPlaybackStep`),
  applied inside `EngineController.resolvedStepNotes` (both precompute and
  live read it — equivalence rail untouched; density 0 is a byte-identical
  pass-through). ENGINE ROUTING: `generationAffecting` introduced on
  `TrackMacroDescriptor` (stored, default false, codable-migrated) and
  `PhraseLayerDefinition` (density macroRow); `setMacroLayerDefault`
  consults the flag and routes flagged bindings to the snapshot-install/
  revision-bump path (chord-context precedent 4e0ba807) while dispatch-only
  macros keep the 426c0771 scoped-runtime fast path
  (SessionDestinationMacroTests extended both ways). AC1-AC5 pinned by
  GeneratedSourceEvaluatorTests (determinism/loop-stability, monotonic
  property across density pairs, cluster distributions, ghost velocity/
  pitch policy, zero-density pass-through) +
  SequencerSnapshotCompilerSemanticsTests (compiled density value,
  end-to-end loop-stable ghosts, superset-of-density-0) +
  SessionDestinationMacroTests (both AC4 routes); all three realtime lints
  + ux-canon green. AC6: rows 10a/10b wired (`phraseDensityValue` runner
  vocab, density 0 vs 0.6); capture pass pending an attended
  visual-automation session (unattended TCC gate).

- 2026-07-03: WS4 delivered on `feat/ws4-generators` (salvage peel from the
  wip/ws-batch-snapshot batch, rebased onto post-WS3 main; WS5 density and
  WS6 scene-membership hunks left in the snapshot). Vocabulary: StepAlgo
  gains `weighted(weights:steps:cluster:)` (bipolar cluster) + `manual`;
  PitchAlgo gains `pool(root:scale:spread:selection:deviation:)` with the
  SELECTION memory axis and the DEVIATION family (accidentals / octave span
  / chromatic leading). Pool semantics: scale INTERSECT chord filter — the
  sidechain re-pools pitch selection and never touches triggers
  (GeneratorVocabAcceptanceTests mid-run chord-change fixture pins
  trigger-stream byte-invariance). Chromatic leading is sequence-aware: an
  approach tone RESOLVES stepwise into a pool note on the next fire. AC1
  stable identity: `GeneratorPoolEntry.switchingKind` +
  `session.switchGeneratorKind` mutate in place (same UUID, slot refs +
  shared root/scale/velocity carry; GeneratorPoolEntryTests +
  SessionBatchHelperTests). AC3/AC5: the frozen PrecomputeBarEquivalence
  rail is extended (not edited) by GeneratorVocabAcceptanceTests — new algo
  kinds precompute == live under fixed seeds, and the editor's result strip
  renders `GeneratorResultStrip.barContent` (the shared evaluator), pinned
  == the precomputed bar for a deterministic fixture. Editor per 14b:
  header mode chip (in-place switch) + FOLLOWING chip + Bake dice (wired to
  `session.bakeGeneratorToClip` — realized bar frozen into a new clip on
  the slot), always-visible result strip, TRIGGER|PITCH stage tabs in the
  inset-track StudioSegmentedControl family (snapshot's native segmented
  pickers replaced; pre-existing native pickers inside PitchAlgoEditor kind
  rows left as prior art). WS3's interim GENERATED/READ-ONLY badge removed
  per its documented deferral — the result strip + Bake dice carry the
  signal. AC6: the editor lives in WorkspaceDetailView's ScrollView
  (internal scroll, canon Rule 8) AND the pitch stage takes the tighten
  option (deviation trio in one knob row, no meta-text column). Canon:
  weighted kind accent is violet, not the snapshot's amber (amber fenced to
  pending). AC7: rows 22e-22h wired (trackGeneratorStage/Kind/Following
  runner vocab); capture pass pending an attended visual-automation session
  (unattended TCC gate).

- 2026-07-03: WS6 delivered on `feat/ws6-scene-inputs` (salvage peel from the
  wip/ws-batch-snapshot batch, re-knit against post-WS5 main). Model:
  `TrackMixSettings.SceneMembership` (A / B / both, equal-power
  `gain(crossfader:)` — cos/sin quarter-wave, nil crossfader = unity) with
  spec default `.both` and `decodeIfPresent ?? .both` migration (AC4).
  Engine: the membership gain multiplies into `effectiveMix` for AU hosts
  and audio-input routing requests, and rides a NEW dedicated RAMPED
  scene-gain stage on the sample engine (`setTrackSceneGain`, mirrors the
  `setTrackMuteGain` shape on the same per-track gain node; effective
  volume = muted ? 0 : level x sceneGain) — the snapshot's variant, which
  pushed the gain through the SNAPPING fader path and re-zeroed the fader
  on mute (a reverse-hunk of the b4701881 mute-as-ramped-gain convention),
  was REJECTED during the peel; that stale pre-b4701881 muted-level scoped
  test expectation is fixed alongside. Live crossfader overrides and
  master-bus applies re-derive member gains
  (`refreshSceneMembershipGains*`), parameter-path only. DEVIATION from the
  behavior sketch, recorded: the gain stage lives per-track upstream
  (track gain stage), not inside MasterBusHost — a non-member track is
  silenced before both scene branches rather than removed from one branch's
  insert chain; AC1-AC5 semantics are met and the crossfader morphs only
  member tracks. Sends: Send A/B knobs/config are byte-identical (353829be
  hard line, AC3) — the scene selector is a Menu chip in the OUTPUT
  selector's grammar, visually/semantically distinct from the send knobs,
  and writes ONLY `mix.sceneMembership`; send-leg gains are not scene-gated
  (scenes-x-sends interaction deferred with the FX-return design). AC
  evidence: AC1 model curve (MasterBusStateTests gain test) + controller
  gains (EngineControllerSetMixScopedTests membership test: B-only at full
  A -> sceneGain 0, sends untouched) + offline RMS render per membership x
  crossfader-extreme (MasterRenderTests
  test_sceneMembershipGainSilencesNonMemberTracksInManualRendering —
  WRITTEN but environment-red on the delivery machine: the whole
  manual-render family fails -80802 identically on clean origin/main,
  verified by stash/run; re-run when coreaudiod recovers). AC2:
  RampBeforeDisconnectTests
  test_sceneMembershipChange_soundingTrack_rampsGainStage_notHardCut GREEN
  (sounding chokepoint ramps 0.8 -> 0 -> 0.8, no synchronous hard-cut);
  the two pre-existing route-switch live tests are identical-red on clean
  main (environment). AC3: send byte-identity pinned by
  MasterBusStateTests test_trackMixSceneMembership_leavesSendValuesByteIdentical
  + the scoped membership test. AC4/default: legacy-JSON decode test ->
  both. AC5: rows 06c (phraseSceneMembershipFixture=split scenes readout)
  and 22ba (trackSceneMembership=sceneA routing selector) wired; capture
  pass pending an attended visual-automation session (unattended TCC
  gate). Gates: MasterBusState 24/24, SetMixScoped 6/6,
  SessionMasterBus 21/21, MasterBusHost 14/14, QuantisedToggle 11/11,
  SessionDestinationMacro 9/9, TrackFillPreview 5/5,
  OfflineFrameAccuracy 14/14, app build, four lints rc=0;
  MasterRender/MixerBusRoutingReconnect(live)/RampBeforeDisconnect(route-
  switch pair) identical-red on clean origin/main this machine.
