# Foreman state

## OVERNIGHT BUILD-OUT: perform/setup split (Max approved 2026-06-12 eve)

Authority: docs/roadmap/perform-setup-split/ (intent-dictation,
wireframes, rytm-study). "Big build out with sensible decisions, look
tomorrow." Slices in order (each: worktree → gate → land):

>> MODEL SWITCH 2026-06-15: Fable became inaccessible; foreman now on
>> Opus 4.8. Slices 1+2+3 LANDED on main (01f0586a). Slice 3
>> (perform-overview) was Fable WIP — preserved as 37bbe29d, then
>> finished+gated (1482/0, 15 new tests) and merged. Slice 4
>> (routing-tab) LANDED (16ef7d49, gate 1489/0) — FIRST slice through
>> a TRIALLED ADVERSARIAL CRITIC pass (fresh-context refutation review
>> before merge); critic confirmed substance clean, found one nit.
>> Slices 5-7 ready to resume under the Foreman Coordinator shape.
>> HANDOFF.md governs the cautious posture.
>>
>> PROCESS DECISION RESOLVED 2026-06-15: adopt the Foreman Coordinator
>> shape and make the adversarial critic phase standard before landing
>> feature slices. Keep the other tweaks as process backlog, not a
>> blocker: precheck flags skip-list/suppression/xfail deltas vs main;
>> discard-vs-resume rules for interrupted partials; N-version search
>> audits for exploratory work. Build-out resumes at slice 5
>> capture-edits.
>>
>> SLICE 5 IN PROGRESS: ~351 lines of interrupted capture-edits build
>> found uncommitted in the worktree → PRESERVED (33917956) →
>> critic-read verdict FINISH IN PLACE (feature-complete vs §3, reuses
>> phrasePerformOverlay, one compile blocker: missing
>> trackPerformCaptureRenderedVisualState Notification.Name).
>> Finish-and-gate agent dispatched (fix+gate, NO merge). On its green
>> return: run the MANDATORY adversarial critic pass, then land. Slices
>> 6-7 follow.
>>
>> SLICE 5 PRODUCT FORK RESOLVED BY MAX (2026-06-15): perform-mode
>> tracks should use the existing layered track-card matrix; the
>> row-per-track dashboard is not the right shape for this surface, and
>> macros should live somewhere else. Current branch
>> feature/perform-capture-edits contains the capture machinery plus the
>> layout correction (0d51ba80 + 9b0d9300). COREAUDIOD RESTARTED AND
>> VERIFIED: full clean gate on the feature worktree passed (1497 tests,
>> 19 skipped, 0 failures) and the previously skipped HAL selection passed
>> directly (5 tests, 0 failures). Local adversarial checklist review
>> found no new landing blocker after the matrix correction; the only
>> process note is that the old PerformOverviewDashboard file remains
>> unreferenced and is parked in attention for a repurpose/delete ruling.
>> Remaining before main landing: merge through a clean main checkout (main
>> is currently dirty with unrelated Foreman/migration work). Slices 6-7
>> wait behind the land of slice 5, not behind another product answer.
>>
>> TIDY (nit, no rush): rename TrackRoutingTabContent ->
>> TrackSourceRoutingTabContent for sibling-naming consistency; ride a
>> future slice that touches the area (avoid a standalone re-gate). Deferred-feature seams the perform
>> overview exposes (intentional, per brief): VOLUME/STEP-ORDER/PAN
>> perform layers show a placeholder note; audio-in fill/repeat
>> slots inert; macro rack surfaces only active-scene macros;
>> monitor column is a readout (patterns-own-source deferred).
  1. global-mode — session-level SETUP/PERFORM in the top bar
     REPLACING the tracks edit/perform + scenes browse/perform local
     toggles (wireframe §0/§1). Capture fixture protocol must keep
     working (map old mode commands).
  2. quantise — generalize pending-at-boundary for perform toggles
     (mute/fill/repeat/pattern): Q setting (OFF/BAR), arm visual
     (dashed amber), MOM/LATCH/+CYCLE gestures (§2, Rytm fill).
  3. perform-overview — DECISION: the overview IS the perform-mode
     tracks surface (merge §1+§9): one row per track (pattern, fill,
     repeat, mute), kit = one colour row, macro rack strip below.
  4. routing-tab — destination column → ROUTING tab (instrument → FX →
     dest/sends, pill summary; ◎ macro-assign stubs to rack) (§8).
  5. capture-edits — dirty rings + counter + CAPTURE arming 4x4 phrase
     matrix + REVERT sibling (§3, save-arm grammar).
  6. kit-default + Sound panel — drum track opens on kit matrix;
     part/slice Sound view (player + sends; per-part FX chains NOT
     invented overnight — panel notes future FX slot) (§5/§10).
  7. (stretch) slicer sequence row (§6/§7b step scope only).
DEFERRED DELIBERATELY: audio-in patterns-own-source (§4) — engine
rework needing spec+prototype approval, not an overnight wing; global
macro rack full assignment model (only the rack strip + promote stub
ships); per-part FX chains.
Morning deliverables: all landed slices gated; app built; captures +
gallery refreshed at first unlock; attention list updated with taste
calls found en route.

Last tick: 2026-06-11 (seeded manually during setup; this session acted as
the trial tick).

## In flight

- kits/templates MERGED to main (Max approved, gate green, 1298 tests
  post-merge). Worktree and branch now cleaned up.
- The 2026-06-11 morning bug reports: RESOLVED by the ux-bug-sweep merge
  (158bf031) — each has a resolution.md. Visual verification against
  captures still pending console unlock.
- The two intent-drift feedback files are now DISPATCHED (no longer
  pending a lens): drift verified real on main 2026-06-11 (StepGridView
  still hard-codes isSelected:false; ClipStepInspectorSheet still the
  inspect path; clip-history multipass loop is status:complete so its
  post-merge feedback is foreman-owned).
  - feature/track-source-step-grid: DONE and MERGED to main (0b5d8de3,
    fast-forward to the gate-tested tree, 1325/0). Variant D rotary row
    shared from the slicer; ClipStepInspectorSheet deleted; selection
    composes in StepGridView. Worktree/branch removed. Follow-ups noted
    in its resolution doc: batch action bar not surfaced in Track
    Source; macro "clear override" double-click superseded.
  - feature/clip-history-corrections: DONE and MERGED to main (save-arm
    state machine, live rolling preview with step dividers + pitch rows,
    clip-source capture; Refresh was already gone on main — auto-poll is
    the mechanism; gate 1326/0 in worktree). Post-merge suite GREEN on
    main; worktree and branch removed.
    Known limitation noted in resolution: live fill marker assumes
    16-step bars.
- Codex interim work VERIFIED AND LANDED on main as e56c5f75 (full suite
  green first): BuildIdentity surfaced in top bar/logs (resolves the
  observability visible-build-identity feedback — resolution written;
  multipass loop's parallel partial work in
  .worktrees/roadmap-21-observability-log-issues needs reconciling by
  its decider), master-bus unity pass-through, sample-accurate voice
  starts, master render test coverage.
- Max's five 2026-06-11 afternoon bugs, triaged. Dispatch queue (max two
  concurrent agents; pop when a slot frees):
  1. small-UI sweep — DONE and MERGED to main (3 commits, suite green
     in worktree; post-merge suite running). DELIBERATE BEHAVIOR CHANGE
     flagged for Max: the Tracks edit-mode chevron layer-cycler was
     replaced by the perform-mode selector, so cycler-only layers
     (transpose, intensity, density, tension, register, variance,
     fx-send, brightness, swing, per-track macros) are no longer
     reachable from the Tracks page — still editable on Live page.
     Post-merge suite: one failure (ObservationGranularityTests runner
     bootstrap crash + mkstemp result-bundle errors) — infrastructure
     under disk pressure, passes in isolation. Main GREEN. Worktree and
     branch removed.

## Machine: disk at 95% (11Gi free)

Three concurrent builds squeeze temp space (caused the bootstrap
flake above). Foreman must not rm -rf outside capture dirs; stale
~/Library/Developer/Xcode/DerivedData and old worktree build-dd dirs
are the likely bulk. Flagged to Max in attention; until freed, prefer
max ONE agent build concurrent with any main-checkout suite.
  2. mixer overhaul — DONE and MERGED to main (b3e6b23b, fast-forward
     to gate-tested tree, 1365/0 + combination gate green). All ten
     143027 rulings + StudioMixerStrip scaffold + ChannelMeterBank
     metering on all strips (roadmap 29 core done; its cosmetic
     "No default output" wording fix remains). Caveats noted in
     resolution: AU track meters silent until instrument loads;
     compact <540pt layout kept the master drawer (flagged for visual
     QA). Worktree/branch removed.
## Active priority: solidity audit (Max, 2026-06-12)

All three audits COMPLETE (docs/audits/2026-06-12-*) + a live-sampled
deadlock (Max hit it: Add FX on send bus → graph-lock self-deadlock;
sample preserved). Wave 1 LANDED on main (6b26b585, gate 1354/0 twice):
sampled deadlock + D1-D4 + races + latency trio + single meter pump,
with regression tests, debug lock-hold assertions
(stateLockHoldViolationHandlerForTesting hook), and counting hooks
(sendBusTopologyInstallCountForTesting,
reconnectTrackOutputCountForTesting). Ear-checks queued (attention 1).
Behavior change to watch: insert-less scene crossfade no longer sums
identical branches (~+3dB mid-fade gone). Overnight progress:
  a. DONE+MERGED: tracks-invalidation (17cff79f) — playhead-leaf
     scoping, tick-path watchdog, observation-budget rule. Both halves
     of the BPM sag now fixed (engine hops: wave 1; UI scope: this).
  b. DONE+MERGED: step-grid-unify (5b083cc8, ff; gate 1425/0 with the
     two-test skip list). One edit-semantics implementation
     (ClipNoteGridStepEditing), one clip-write path
     (StepGridCoordinator.commitEdit), optimistic tap latency
     preserved + pinned, lost-update regression test added. FOUR
     parity divergences resolved against spec (documented in
     StepGridEditParityTests header) — behavior changes for Max's
     fingers: velocity clamps at the edit; macro tap cycles quantized
     allowed values; multi-select option-cycle applies the tapped
     target to the whole selection.
  c. DONE+MERGED: capture-save-inversion (87d4f490; gate 1425/0).
     The engine now NEVER writes the document (F8 inverted; saves
     converge on saveMaterializedClipToPatternSlot); dead
     ClipMacroLaneEditor deleted.
  g. DONE+MERGED: tick-hop-final (c6f39ee9; gate 1401/0, tick median
     51µs under load). ZERO tick-path main hops remain;
     TickPathMainSyncGuard default is now a DEBUG TRAP. The verdict
     doc's rule 1 is mechanically enforced.

## DONE: EngineController carve-up (9bb3f415, 16:30)

EC 578->330 CCN across four verbatim extension extractions; gate
1426/0 twice + stress + isolation; zero test touches. The metric
hotspot is dealt with. STILL QUEUED from the metrics review: split
VisualScenarioCommandRunner per-workspace + tag harness files in the
metrics script (small). True coordinator-with-owned-state extraction
remains possible later but requires deliberate stateLock re-scoping —
an architecture decision, not a refactor; park unless Max asks.

## SOLIDITY PROGRAM COMPLETE (2026-06-12 ~08:40)

Every slice from Max's "focus on this overnight" order is landed and
gate-verified on main. Engineering queue is EMPTY except the future
processTick 32-track-knee optimization. Remaining items all need Max:
disk (WhatsApp 79G), coreaudiod restart (then verify the last 2
skipped tests and empty the skip list), wave-1 ear-checks, step-grid
finger-checks, flat-UI tweak feedback, captures refresh on unlock.
  d. DONE+MERGED: concurrency-lane (baa46b7d, ff; gate 1411 executed,
     sole failure = the documented coreaudiod machine-state test).
     TSan lane live (scheme + suppressions + lane doc); churn stress
     net (2 in-gate smokes + 5 env-gated loops, all green); lock
     discipline mechanized at every hop helper; SamplerFilterNode tick
     hop removed. TSan first run: 13 reports -> 4 findings, 1 real
     product race FIXED. Double-schedule REFUTED (foreman's +2 was the
     test's stale literal; each entry schedules exactly once). Stash
     dropped.
     SKIP-LIST CHANGE: test_audioInputLoopModeWithRecordedLoopEnters-
     OnNextBarBoundary now PASSES — new standard skip list is ONLY:
       -skip-testing:SequencerAITests/EngineControllerTests/test_audioInputRouting_documentOutputBusMutationPreservesActiveSendFanoutWhileRunning
       -skip-testing:SequencerAITests/MainAudioGraphDeviceSwitchTests
     (both pass only with healthy coreaudiod; drop entirely after Max
     restarts it and they're verified green).
     NEW FOLLOW-UP: audio-input capture-format read at record start is
     still a tick-path sync hop (un-waived; guard default stays log
     until it's removed — then flip to trap).
  e. PROCESS FIX (foreman, low priority): precheck should fingerprint
     dirty-worktree state of foreman branches — parked agent work
     currently reads as "idle".
  f. NEEDS MAX: coreaudiod is degraded (two ~18-min HAL stalls with
     confirmed stacks) — `sudo killall coreaudiod` or reboot; HAL-start
     tests can't pass until then (also in attention).
DONE+MERGED: render harness (0ab522cb) — 9/9 scenarios on-grid
(<=0.5ms), bit-identical renders, smoke tests in default gate.
HEADLINE NUMBER: processTick knee at 32 tracks (p95 132ms > 125ms
budget, debug build); 16 tracks comfortable. Optimization target for a
future slice; sweep can watch the knee in CI.
The audits' "sound patterns" lists protect good code from future
'fixes'. Captures of merged main pending next unlock. Ear-checks for
Max after wave 1 lands: slider feel, AU preset browser during playback,
Add FX on send bus.

  3. flat-UI variant — MERGED TO MAIN (Max approved). History: PASS 3 etc.
     previously PARKED AND FULLY VERIFIED
     (feature/flat-ui-variant @ 5dfabd42). History: pass 1 washed out
     (Max); pass 2 collapsed the grey value stack; pass 3 enforced the
     color grammar after Max found surviving translucent accent floods
     (scene cards, perform cards, track-source nesting) — 88-site
     audit, grammar now ux-canon rule 12 on the branch. Suite green,
     captures verified against his three screenshots. Awaiting verdict
     (attention 1). His pass-2 screenshots came from live app use, not
     the QA rows — worth remembering that captures alone under-sample
     selected/perform states.
- QUEUED (next free build slot): mixer overhaul slice combining
  docs/bugs/2026-06-10-mixer-ux-review.md (shared strip scaffold, pan
  rotaries, master overlay occlusion, dB convergence) with roadmap item
  29 mixer-channel-levels (all strips metered, master as template).
- build-identity feedback remains with its active multipass loop
  (observability-log-issues).
- Multipass build loops continue independently; do not touch their
  worktrees.

## Foreman tick 2026-06-11 ~12:23 (partial — interactive session active)

Max is mid hardware-validation of audio input in this session; build- and
capture-contending triage deferred per resource rules. Done this tick:
resolutions written for mixer-tab-hang and fill-preview-placement feedback
(both verified fixed). Classified the rest:

- build-identity feedback: ACTIVE multipass work (observability loop) —
  not the foreman's to resolve; leave its fingerprint entry pending.
- 9 bug reports (UI polish: wasted space, card noise, single/inherit
  bars, destination panel, sample player, phrase title) + 11 remaining
  feedback files (clip-history x3, layer-matrix-shape, scene/scenes/step
  prototypes feedback, track-source x2, multiselect-latch x2): NEXT
  non-contended tick — most bug reports look like one ux-canon sweep
  (rules 1/3/10) over the track page; batch as patterns.
- feature/drum-kits-and-templates local branch is merged but deletion is
  permission-gated — Max: `git branch -d feature/drum-kits-and-templates`.

## Next tick should check first

- Whether the interactive session has ended (then run the deferred
  triage above, including the full-suite gate over the audio-input
  changes).
- The eight 2026-06-11 bug reports (triage rules apply).
- New entries in `docs/bugs/` (the bug app writes here continuously).
- The two real-hardware CoreAudio tests
  (`MainAudioGraphDeviceSwitchTests`, the input-wiring engine test) pass
  only when coreaudiod is healthy; if they fail with the kAUStartIO/990s
  signature, that is machine state, not code.

## Autonomous phase (Max away, 2026-06-11 ~12:45)

Standing instruction: clear all intents and bugs; park ear-dependent
audio validation; master-render-to-file shipped (graph+engine+tests).

In flight:
- feature/ux-bug-sweep MERGED to main (158bf031, all 9 bug reports
  resolved with resolution.md files). Post-merge on main: xcodegen run,
  Info.plist keys intact, suite green except
  TickClockTests.test_tick_intervals_match_expected_bpm — wall-clock
  flake under load, passes in isolation (rerun verified).
- feature/library-pools MERGED to main (fast-forward to 82ba0289 after
  merging main into the branch; gate suite green on the identical tree
  in the worktree, evidence inherited exact-commit). LibraryWorkspaceView
  conflict resolved toward the branch's real library page.
- Capture evidence CURRENT as of 22:10: main (f45f4d86) and
  flat-ui-variant (6cf44226) both captured (rows 01-42); galleries +
  side-by-side compare at http://100.106.96.34:8765/ (served from
  captures/). A ux-canon observer pass over the new main captures is
  still worth a future non-contended tick.
- Worktrees .worktrees/bug-sweep and .worktrees/library-pools removed;
  branches feature/ux-bug-sweep, feature/library-pools and
  feature/drum-kits-and-templates deleted (all fully merged).

Parked for Max's ears (attention list): buffer playback audibility
(self-healing retry landed but unheard), input monitoring through EVO16,
record-length click (trace added, needs one repro).

Done this phase: intents inbox processed (roadmap items 28, 29); master
render to file landed with tests; 9 stale feedback resolutions (2 left
for the intent-drift lens: step-sequencer track-source-gap, clip-history
live-buffer-save-arm).

CAUTION (self): stage explicit paths only — `git add docs/roadmap` swept
~30 untracked PM artifacts into 2dd2cb5c (kept; they are durable docs).

## Known machine-state hazards

- NEVER remove a worktree (or delete a build-dd) while its built app may
  be running — deleting the bundle under a live process hangs it with
  LaunchServices/IconServices "bundle does not exist" storms (happened
  2026-06-11 21:36, pid 22781, Max had the variant app open). Check
  `pgrep -x SequencerAI` + the running bundle path first; relaunch him
  from main's build before cleanup.

- TCC mic prompts re-arm on every rebuild (ad-hoc signing). The capture
  harness is hermetic against this; interactive use prompts only via the
  explicit Enable Microphone button.
- Capture runs require an unlocked console; coordinate via the unlock
  check, never retry blindly.
- `Sources/Resources/Info.plist` loses keys to xcodegen churn; diff
  against HEAD after any generate/merge.
