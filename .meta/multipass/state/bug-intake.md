# Bug Intake Observation

- updated: 2026-07-06T17:27Z
- request: `.meta/multipass/runtime/inbox/claimed/2026-07-06T121447692Z-bug-observer-cadence.md`
- loop-local copy: `.meta/multipass/runtime/loops/project/observe/2026-07-06T17-27Z-bug-intake-observation.md`
- scope: unresolved owner bug folders under `docs/bugs/` that lack `resolution.md`.
- checked: request file, unresolved `docs/bugs`, existing bug intake, compact work/readiness/holistic state, relevant build-loop summaries, `.foreman` state/attention/decisions, and root git status.
- note: this observer did not edit bug folders or route work. Folders lacking `resolution.md` remain open intake even if a note/report already contains `Status: RESOLVED`.

## Current Count

- folders lacking `resolution.md`: 160.
- of those, 111 already contain resolved-status text in a note/report and mainly need resolution-file/process closeout if the evidence still holds.
- folders lacking both `resolution.md` and resolved-status text: 49.
- active ordinary build loops now observed: `build/au-runtime-safety` and `build/track-setup-surface-compression`.
- recently closed: `build/drum-kit-matrix-sound-prep` is complete as a read-only seam check, not an implementation-complete feature claim.

## Groups

### G1: AU Discovery / Rescan / Picker Ordering

- status: `probably-resolved-missing-resolution`
- scope: `process-repair`
- priority: `medium`
- routing_hint: audit current-main AU picker/rescan evidence and write missing `resolution.md` only where fixed; do not duplicate active AU runtime-safety work.
- evidence: `build/au-discovery-rescan` is terminal complete by current-main supersession; `docs/bugs/20260616-au-plugin-list-needs-rescan-without-relaunch` and `docs/bugs/20260704-075604-let-s-put-the-aus-at-the-top-then-sample` have resolved text but no `resolution.md`. `docs/bugs/20260616-104317-plugins-are-missing-from-the-list-of-eff` still has no resolved text.
- bugs:
  - `docs/bugs/20260616-104317-plugins-are-missing-from-the-list-of-eff` - plugins missing/truncated in effect list; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260616-au-plugin-list-needs-rescan-without-relaunch` - runtime rescan without relaunch; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260704-075604-let-s-put-the-aus-at-the-top-then-sample` - AU-first picker ordering and rescan placement; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260705-193532-let-s-make-the-aus-one-colour-border-the` - sound-step border colors; `needs-triage`, `feature-follow-up`, `medium`.

### G2: AU Runtime Safety / Presets / Removal

- status: `already-routed`
- scope: `active-build-loop`
- priority: `urgent`
- routing_hint: wait for `build/au-runtime-safety`; full owner-bug closure needs human-present third-party AU validation or explicit acceptance of that evidence gap.
- evidence: `.meta/multipass/state/build-loops/au-runtime-safety.md` is active for these owner bugs, with deterministic checkpoint `ead7586f` held on manual AU validation.
- bugs:
  - `docs/bugs/20260624-165547-the-preset-picker-for-an-au-instrument-i` - preset picker style/behavior; `already-routed`, `active-build-loop`, `urgent`.
  - `docs/bugs/20260629-101847-au-preset-no-change-during-playback-and-hung-note` - preset does not change sound / hung note; `already-routed`, `active-build-loop`, `urgent`.
  - `docs/bugs/20260629-121929-au-removal-while-playing-crash` - removing AU while playing crash; `already-routed`, `active-build-loop`, `urgent`.

### G3: Mixer Strip Polish / FX Wells / Stopped Meters

- status: `probably-resolved-missing-resolution`
- scope: `process-repair`
- priority: `medium`
- routing_hint: close out fixed mixer bugs with `resolution.md` after confirming current-main evidence; only route a new mixer follow-up for regressions not covered by `04a0e071`/later status text.
- evidence: `build/mixer-strip-followup` is complete and merged to local main at `04a0e071`; many notes contain `Status: RESOLVED`. Fresh July 6 send-height note says resolved pending commit with verification capture, but still lacks `resolution.md`.
- bugs:
  - `docs/bugs/20260616-104459-master-channel-strip-is-too-wide-scene-a`
  - `docs/bugs/20260616-104743-i-don-t-really-like-the-style-of-the-lev`
  - `docs/bugs/20260616-105006-the-third-button-here-on-the-channel-str`
  - `docs/bugs/20260616-105141-this-is-in-the-send-channel-it-should-sa`
  - `docs/bugs/20260616-115937-when-the-transport-is-stopped-the-levels`
  - `docs/bugs/20260618-135348-instead-of-the-dropdown-make-a-plus-butt`
  - `docs/bugs/20260618-135534-tidy-up-the-fx-on-the-left-draggable-han`
  - `docs/bugs/20260620-134440-the-pan-controls-have-been-fixed-channel`
  - `docs/bugs/20260620-153143-sends-are-falling-out-of-the-box`
  - `docs/bugs/20260620-202952-let-s-use-the-same-ui-view-for-mixer-on`
  - `docs/bugs/20260624-164500-mixer-send-channel-ui-regression`
  - `docs/bugs/20260629-095947-send-strip-fx-insert-too-heavy-name-only-modal`
  - `docs/bugs/20260629-140925-there-was-a-fix-made-to-send-channels-so`
  - `docs/bugs/20260705-193605-the-send-channels-should-be-the-same-hei`
  - `docs/bugs/20260705-195208-the-empty-fx-well-should-be-black-not-gr`
  - `docs/bugs/20260706-104649-send-a-and-b-channels-are-shorter-than-t`

### G4: Scene FX / Filter UI

- status: `needs-triage`
- scope: `feature-follow-up`
- priority: `medium`
- routing_hint: route one focused Scene FX visual grammar pass after higher-priority active loops clear.
- evidence: unresolved reports cluster around filter controls, redundant FX title, plus-button empty state, and add-FX modal capture state; some older scene-FX notes have resolved text but no `resolution.md`.
- bugs:
  - `docs/bugs/20260618-135652-make-the-filter-plugin-less-ugly-use-rad` - filter UI/radials/curve visualization; `needs-triage`, `feature-follow-up`, `medium`.
  - `docs/bugs/20260619-212622-the-filter-type-needs-better-ui-elements` - filter type control style; `needs-triage`, `feature-follow-up`, `medium`.
  - `docs/bugs/20260619-212650-the-fx-title-is-useless` - remove redundant FX title; `needs-triage`, `feature-follow-up`, `medium`.
  - `docs/bugs/20260619-212730-instead-of-no-effects-yet-ther-should-be` - empty FX plus button; `needs-triage`, `feature-follow-up`, `medium`.
  - `docs/bugs/20260620-135118-this-is-still-an-awkward-view-i-think-th` - add-FX empty state, resolved text; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260620-135233-when-there-are-fx-in-the-scene-the-fx-bu` - FX button placement, resolved text; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260623-130451-this-capture-is-wrong-the-add-fx-window` - capture should close add-FX window; `needs-triage`, `process-repair`, `low`.

### G5: Drum Kit / Kit Matrix / Drum Part Sound

- status: `needs-triage`
- scope: `feature-follow-up`
- priority: `high`
- routing_hint: use `build/drum-kit-matrix-sound-prep` as seam evidence, but route actual implementation work separately only for violations not already satisfied by current main.
- evidence: `build/drum-kit-matrix-sound-prep` closed as a read-only seam-check checkpoint with tests/canon evidence and visual gap, explicitly not as whole-feature implementation. Several notes have resolved text; several July 5 drum-kit reports remain fresh.
- bugs:
  - `docs/bugs/20260618-135941-let-s-have-the-name-of-each-drum-part-to` - left part-name column, resolved text; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260618-140108-drum-kit-step-sequencer-should-be-limite` - 16-step kit pager, resolved text; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260619-203126-type-the-drumkit-rendered-visual-state-p` - typed rendered visual state; `needs-triage`, `process-repair`, `low`.
  - `docs/bugs/20260620-102115-patterns-and-kit-matrix-are-wasting-spac`
  - `docs/bugs/20260620-102248-also-kick-inline-part-controls-and-open`
  - `docs/bugs/20260620-173816-this-view-is-bad-fx-interface-should-mir`
  - `docs/bugs/20260620-203459-we-re-wasting-too-much-vertical-space-at`
  - `docs/bugs/20260620-203545-wasted-space-for-kit-fx-line-and-subtext`
  - `docs/bugs/20260620-203610-more-wasted-space-see-previous-comments`
  - `docs/bugs/20260620-203657-wasted-space-etc`
  - `docs/bugs/20260622-124324-the-add-drum-kit-modal-needs-to-be-part`
  - `docs/bugs/20260623-131730-i-think-we-get-rid-of-this-view-and-capt`
  - `docs/bugs/20260623-131943-there-s-stuff-here-that-doesn-t-represen`
  - `docs/bugs/20260623-132043-add-kit-effect-modal-blocks-the-view`
  - `docs/bugs/20260623-132053-add-kit-effect-modal-blocks-the-view`
  - `docs/bugs/20260623-132057-add-kit-effect-modal-blocks-the-view`
  - `docs/bugs/20260624-161342-i-should-also-be-able-to-load-an-au-as-t`
  - `docs/bugs/20260626-095529-on-the-tracks-page-make-kit-tracks-show`
  - `docs/bugs/20260629-101345-drum-part-sound-source-empty-vs-none-and-load-au-affordance`
  - `docs/bugs/20260705-150256-let-s-leave-out-the-routing-part-it-shou`
  - `docs/bugs/20260705-195311-get-rid-of-kit-wide-macro-sweeps-text-ma`
  - `docs/bugs/20260705-195340-this-is-now-inconsistent-with-other-trac`
  - `docs/bugs/20260705-195724-this-is-quite-messy-get-rid-of-the-captu` - resolved pending commit text; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260705-195817-this-needs-to-be-less-grey-and-low-contr`
  - `docs/bugs/20260706-104619-the-create-group-button-at-the-bottom-is` - resolved pending commit text; `probably-resolved-missing-resolution`, `process-repair`, `medium`.

### G6: Track / Phrase Perform Interaction And Selection

- status: `needs-triage`
- scope: `feature-follow-up`
- priority: `high`
- routing_hint: group remaining selection, borders, copy/paste/context-menu, and phrase layer selector issues into the next Track/Phrase Perform interaction PM/build slice; avoid duplicating already-landed mini-cell behavior.
- evidence: `track-phrase-perform-mini-cells` landed at `9c1744ba`; `pm/track-phrase-perform-interaction-prep` is not current unpromoted supply. July 5 reports add fresh interaction semantics beyond the mini-cell fix.
- bugs:
  - `docs/bugs/20260616-110235-the-behaviour-of-pattern-layer-in-a-cell` - probably covered by mini-cells but lacks resolution; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260619-213241-there-are-too-many-levels-of-navigation`
  - `docs/bugs/20260619-213713-the-cards-for-each-layer-should-be-inter`
  - `docs/bugs/20260619-213834-it-should-switch-fully-when-in-track-sel`
  - `docs/bugs/20260619-215229-tracks-perform-should-be-navigation-not-layers` - resolved text; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260620-112546-remove-unnecessary-text-in-the-new-nav-b`
  - `docs/bugs/20260620-135423-the-capture-button-is-not-the-right-styl`
  - `docs/bugs/20260620-135607-there-s-still-phrase-in-the-nav-which-is`
  - `docs/bugs/20260620-135925-choose-phrase-layer-is-unnecessary-text`
  - `docs/bugs/20260620-140815-the-orange-container-around-the-bottom-s`
  - `docs/bugs/20260620-172839-the-element-at-the-bottom-should-be-in-t`
  - `docs/bugs/20260620-172957-switch-the-two-menus-around-so-the-three`
  - `docs/bugs/20260622-123930-we-need-an-option-in-the-top-right-of-th`
  - `docs/bugs/20260622-124825-the-value-and-automation-buttons-are-too`
  - `docs/bugs/20260622-125244-the-indicator-with-no-perform-changes-ca`
  - `docs/bugs/20260622-130446-the-track-selector-has-several-issues-th`
  - `docs/bugs/20260622-130618-make-this-3-columns-wide-lose-the-grey-t`
  - `docs/bugs/20260622-181714-on-this-view-i-wanted-the-orange-box-wit`
  - `docs/bugs/20260623-130017-capture-and-discard-should-be-to-the-lef`
  - `docs/bugs/20260623-130843-this-capture-is-wrong-the-phrase-copy-wi` - capture modal closure; `needs-triage`, `process-repair`, `low`.
  - `docs/bugs/20260623-134328-can-we-tidy-this-let-s-make-it-more-visu`
  - `docs/bugs/20260623-134959-the-actual-matrix-has-regressed-here-int`
  - `docs/bugs/20260704-080905-each-cell-should-have-a-border-it-s-not`
  - `docs/bugs/20260704-081015-each-cell-should-have-a-border-i-think-d`
  - `docs/bugs/20260704-081150-the-track-cells-matrix-should-disappear`
  - `docs/bugs/20260704-081215-cells-should-be-the-same-height`
  - `docs/bugs/20260704-081347-all-and-clear-should-be-reduced-height-t`
  - `docs/bugs/20260704-085618-the-layer-buttons-should-be-less-long-to`
  - `docs/bugs/20260704-091036-layers-buttons-should-be-narrower`
  - `docs/bugs/20260705-102035-all-tracks-should-have-a-border-that-is`
  - `docs/bugs/20260705-102540-when-a-track-is-selected-allow-copy-and`
  - `docs/bugs/20260705-102958-right-click-a-cell-here-to-show-more-men`
  - `docs/bugs/20260705-103104-the-text-should-be-bigger-maybe-centrall`

### G7: Scenes / Scene Perform IA

- status: `needs-triage`
- scope: `feature-follow-up`
- priority: `high`
- routing_hint: route one scene-management / phrase-scene-perform IA polish pass with screenshots; keep separate from locked `scenes-in-phrases` PM unless the decider intentionally expands scope.
- evidence: reports consistently ask for Scene Perform inside current phrase, top-nav Scenes as management, numbered/color-consistent A/B slots, fewer containers, and simpler slot views. Some July 4 scene reports have resolved text but July 5 follow-ups remain open.
- bugs:
  - `docs/bugs/20260619-212935-this-page-shouldn-t-exist-scene-perform`
  - `docs/bugs/20260622-125414-this-scene-perform-view-in-phrase-should`
  - `docs/bugs/20260622-125539-take-out-grey-text-include-scene-select`
  - `docs/bugs/20260622-125642-take-out-this-text-on-scene-perform-page`
  - `docs/bugs/20260704-075957-take-out-grey-text-on-scenes-i-think-we`
  - `docs/bugs/20260704-080437-i-don-t-know-why-that-inputs-thing-is-at`
  - `docs/bugs/20260704-080735-too-busy-too-many-interface-containers-e`
  - `docs/bugs/20260704-080817-each-item-has-2-plus-signs-which-makes-i`
  - `docs/bugs/20260705-193840-the-big-number-in-each-cell-should-be-ce`
  - `docs/bugs/20260705-193958-we-don-t-need-scene-name-at-the-top-perh`
  - `docs/bugs/20260705-194029-get-rid-of-the-2-8-text-above-macros`
  - `docs/bugs/20260705-194506-we-don-t-need-this-with-the-new-slot-vie`
  - `docs/bugs/20260705-194642-the-whole-of-the-top-of-each-slot-should`

### G8: Track Setup Surface Compression / Slicer / Sample Player / Audio Input

- status: `already-routed`
- scope: `active-build-loop`
- priority: `high`
- routing_hint: wait for `build/track-setup-surface-compression`; split transient-detection quality if it proves algorithmic rather than UI compression.
- evidence: `.meta/multipass/state/build-loops/track-setup-surface-compression.md` is active for bug-intake G7 plus the fresh July 6 clip-header report. Scope includes normal/slicer/audio setup headers, waveform-adjacent controls, and removal of grey helper copy/noise.
- bugs:
  - `docs/bugs/20260620-114100-this-view-seems-very-crammed-to-the-left`
  - `docs/bugs/20260620-141119-the-sub-text-on-the-source-slice-etc-can`
  - `docs/bugs/20260620-141300-there-s-some-grey-text-underneath-and-ab`
  - `docs/bugs/20260620-141506-sample-present-is-uneccessary-the-white`
  - `docs/bugs/20260620-141957-the-audio-channel-box-has-some-almost-in`
  - `docs/bugs/20260620-173138-collaps-the-track-title-with-pattern-hea`
  - `docs/bugs/20260620-173215-collapse-the-top-of-this-view-like-the-r`
  - `docs/bugs/20260620-173308-collapse-the-vertical-space-around-the-t`
  - `docs/bugs/20260620-173510-audio-channel-box-should-be-simpler-big`
  - `docs/bugs/20260620-191818-sound-source-above-the-well-is-not-neede`
  - `docs/bugs/20260622-124303-let-s-put-clip-length-in-the-left-side-u`
  - `docs/bugs/20260622-124537-the-start-length-etc-controls-can-sit-in`
  - `docs/bugs/20260622-130913-lots-of-wasted-space-here-esp-under-use`
  - `docs/bugs/20260622-131140-remove-duped-source-title`
  - `docs/bugs/20260622-131801-take-out-grey-sub-heading-view-doesn-t-n`
  - `docs/bugs/20260623-131354-there-isn-t-currently-a-way-to-choose-a`
  - `docs/bugs/20260623-131606-i-feel-like-the-transient-finding-and-se`
  - `docs/bugs/20260623-131625-modal-needs-to-be-closed-here`
  - `docs/bugs/20260704-084704-can-we-take-out-the-little-pills-within`
  - `docs/bugs/20260704-084929-randomize-is-a-feature-of-clips-the-butt`
  - `docs/bugs/20260704-085114-the-blue-dot-on-the-4-pattern-button-is`
  - `docs/bugs/20260704-085200-this-should-just-have-a-big-plus-button`
  - `docs/bugs/20260704-085439-this-is-very-grey-the-instrument-and-des`
  - `docs/bugs/20260704-090514-layer-button-should-go-on-same-line-as-l`
  - `docs/bugs/20260704-090801-track-steps-are-too-busy-they-should-use`
  - `docs/bugs/20260704-091011-very-grey-and-washed-out-the-rounded-cor`
  - `docs/bugs/20260704-091143-orange-text-with-no-input-device-can-go`
  - `docs/bugs/20260704-153522-the-top-section-of-slicer-normal-track-k`
  - `docs/bugs/20260705-150325-get-rid-of-grey-subtext-and-line-after-h`
  - `docs/bugs/20260705-194854-this-would-be-a-more-useful-capture-if-i`
  - `docs/bugs/20260706-113305-move-lane-length-layer-chooser-randomize`

### G9: Generator / Modifier UI Clarity

- status: `probably-resolved-missing-resolution`
- scope: `process-repair`
- priority: `medium`
- routing_hint: audit July 4 generator/modifier fixes and write missing resolution files; route only if current captures contradict resolved notes.
- evidence: July 4 generator notes contain resolved status text (`ead444f2`/`4c1259e3`) but lack `resolution.md`.
- bugs:
  - `docs/bugs/20260704-085910-mono-generator-text-is-unreadable-i-m-no`
  - `docs/bugs/20260704-090019-pitch-modifier-and-pitch-expander-headin`
  - `docs/bugs/20260704-090248-i-m-a-bit-confused-about-this-view-it-sa`
  - `docs/bugs/20260704-090330-this-is-also-confusing-the-pitch-modifie`
  - `docs/bugs/20260704-090836-this-bottom-section-is-very-grey-with-us`

### G10: Routing / Audio Graph Safety Defects

- status: `probably-resolved-missing-resolution`
- scope: `process-repair`
- priority: `high`
- routing_hint: audit landed engine-solidity/routing evidence and write `resolution.md`; route only `20260626-route-track-to-mixer-bus-goes-silent` if current routing-stress evidence still reproduces silence.
- evidence: most routing/audio-graph bug reports contain resolved status text from the solidity/routing work; one bus-silence report still lacks resolved text. Audio hard rules apply to any reopened implementation.
- bugs:
  - `docs/bugs/20260622-123804-when-i-add-a-new-drum-track-and-select-a`
  - `docs/bugs/20260623-135100-send-effect-amount-change-hangs-app`
  - `docs/bugs/20260624-170000-add-track-fx-graphlock-reentry-crash`
  - `docs/bugs/20260625-170500-mixer-mute-deadlock-hang`
  - `docs/bugs/20260625-add-second-insert-render-recursion-cycle`
  - `docs/bugs/20260625-add-track-effect-deadlock-hang`
  - `docs/bugs/20260625-realtime-lint-misses-routing`
  - `docs/bugs/20260625-route-to-master-loses-voices-silence`
  - `docs/bugs/20260625-routing-hard-disconnect-clicks`
  - `docs/bugs/20260625-track-mute-trigger-gate-not-gain`
  - `docs/bugs/20260626-au-host-status-readout-deadlock`
  - `docs/bugs/20260626-mute-and-solo-mutually-exclusive`
  - `docs/bugs/20260626-route-switch-teardown-hard-cut`
  - `docs/bugs/20260626-route-to-bus-click`
  - `docs/bugs/20260626-route-to-master-intermittent-silence`
  - `docs/bugs/20260626-route-track-to-mixer-bus-goes-silent` - no resolved text; `needs-triage`, `tiny-main-fix` or `feature-follow-up`, `high`.
  - `docs/bugs/20260626-routed-track-meter-source-and-dest`
  - `docs/bugs/20260626-track-mute-does-not-mute-sends`

### G11: Transport / Global Chrome / Macro Size

- status: `needs-triage`
- scope: `tiny-main-fix`
- priority: `medium`
- routing_hint: small UI polish pass when capacity opens, unless folded into a touched surface.
- evidence: reports are isolated visual polish not clearly owned by current active loops.
- bugs:
  - `docs/bugs/20260623-131016-the-macros-rotaries-can-be-much-bigger-t` - macro rotaries larger, remove labels; `needs-triage`, `feature-follow-up`, `medium`.
  - `docs/bugs/20260629-100436-track-cell-colour-semantics-and-auto-colours` - resolved text but no resolution; `probably-resolved-missing-resolution`, `process-repair`, `medium`.
  - `docs/bugs/20260629-135124-can-we-make-the-gap-on-the-left-of-the-t` - transport left gap / bar height / grey text; `needs-triage`, `tiny-main-fix`, `medium`.

### G12: Visual Capture / Process Repair

- status: `needs-triage`
- scope: `process-repair`
- priority: `medium`
- routing_hint: repair capture scripts/status expectations only when the affected capture rows are next used; do not run TCC-gated capture without explicit permission.
- evidence: mic-permission workaround and capture-modal reports are process/evidence quality issues, not product implementation by themselves.
- bugs:
  - `docs/bugs/20260620-081552-qa-capture-mic-permission-workaround`
  - `docs/bugs/20260623-130451-this-capture-is-wrong-the-add-fx-window`
  - `docs/bugs/20260623-130843-this-capture-is-wrong-the-phrase-copy-wi`
  - `docs/bugs/20260623-131625-modal-needs-to-be-closed-here`

## Decider Signal

1. Highest-value next bug group: keep `build/track-setup-surface-compression` moving; it covers the fresh July 6 clip-header complaint plus the large slicer/sample/header compression cluster.
2. Wait behind active work: AU runtime safety remains held on human-present AU validation; track/setup compression is active. Do not open duplicate AU or setup-surface lanes.
3. Already routed or stale: mixer follow-up, AU discovery/rescan, many July 4 phrase/global/generator reports, and most routing/audio-graph defects appear fixed or superseded but lack `resolution.md`.
4. Process issue: backlog counts are inflated by folders with resolved-status text but no `resolution.md` (111 of 160 unresolved-by-file folders). A process-repair pass should write proper resolution files after confirming current evidence, rather than using those as fresh build supply.
