# Bug Intake

- updated: 2026-06-17T08:13Z
- source observation:
  `.meta/multipass/runtime/loops/project/observe/2026-06-17T08-13Z-bug-intake.md`
- request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-17T081334977Z-bug-observer-cadence.md`
- scope: observation only. No bug folder resolution, inbox routing, request
  lifecycle move, merge, rebase, cleanup, product-code edit, build, test
  suite, visual capture, process repair, lock clearing, or product-owner
  question performed.

## Current Unresolved Bug Folders

Folders below lack `resolution.md` in the main checkout and are therefore open,
even when branch evidence says the work is already routed.

| path | title | status | scope | priority | routing_hint | evidence |
| --- | --- | --- | --- | --- | --- | --- |
| `docs/bugs/20260615-tracks-routing-source-and-mixer-split` | Split routing tab into sound-source and mixer/FX wells | already-routed | active-build-loop | high | Do not duplicate-route. Let `build/routing-source-mixer-split` recover exact sample/slicer `Sound Source` evidence, then review/critic/integration. | Active summary names this owner bug and branch `feature/routing-source-mixer-split`. Direct check: clean at `0f297367` (`Harden routing source capture waits`), `1` behind / `5` ahead of `main`. Current blocker is capture/window/CoreAudio evidence for rows `22d`/`22e`, not new product work. |
| `docs/bugs/20260616-104317-plugins-are-missing-from-the-list-of-eff` | Effects plug-ins missing from list after restart | already-routed | active-build-loop | high | Do not duplicate-route. Let `build/au-discovery-rescan` prove restart-time list completeness and runtime rescan once HAL/CoreAudio evidence is healthy. | Active AU build-loop summary names this owner bug. Direct check: branch `feature/au-discovery-rescan` is clean at `4ce14c75` (`Test AU plugin rescan publication`), `0` behind / `2` ahead of `main`. Current build-loop decision holds on local HAL proxy-stall evidence. |
| `docs/bugs/20260616-au-plugin-list-needs-rescan-without-relaunch` | AU plug-in lists need non-blocking rescan without relaunch | already-routed | active-build-loop | high | Do not duplicate-route. AU lane must prove non-blocking `aufx` and `aumu` rescan without relaunch plus picker/menu state evidence. | Same active AU build loop as above. Note identifies `AudioInstrumentChoiceCache` and `AudioEffectChoiceCache` launch-time cache behavior; active loop acceptance covers effects and instruments. |
| `docs/bugs/20260616-104459-master-channel-strip-is-too-wide-scene-a` | Master strip too wide; Scene A/B labels should sit above slider | unresolved | feature-follow-up | high | Group into one bounded mixer/channel-strip follow-up after capacity opens or deliberate preemption. Require exact mixer screenshots at useful widths. | Fresh owner note plus image. No active route, branch, resolution, build-loop summary, screenshot evidence, or stopped-meter evidence observed for this June 16 mixer cluster. |
| `docs/bugs/20260616-104743-i-don-t-really-like-the-style-of-the-lev` | Mixer level indicator should use draggable blue slider style | unresolved | feature-follow-up | high | Group into the mixer/channel-strip follow-up. Align track levels and master fader on the same draggable blue slider element. | Owner rejects the pale gray rounded level indicator and asks for the draggable blue slider style. Same mixer surface as adjacent June 16 reports; no route or resolution observed. |
| `docs/bugs/20260616-105006-the-third-button-here-on-the-channel-str` | Move channel-strip button and make pan a rotary | unresolved | feature-follow-up | high | Group into the mixer/channel-strip follow-up. Treat this newer owner note as current authority for channel-strip button placement and pan style. | Owner asks to move the third strip button left of the track name and make pan a rotary with the label below. No route or resolution observed. |
| `docs/bugs/20260616-105141-this-is-in-the-send-channel-it-should-sa` | Send channel copy and empty-slot polish | unresolved | feature-follow-up | high | Group into the mixer/channel-strip follow-up. Smallest fix is send-channel `FX` copy plus plus-only empty slot affordance. | Owner says the send channel should say `FX` rather than `Inserts`, with a plus-only empty slot. No route or resolution observed. |
| `docs/bugs/20260616-115937-when-the-transport-is-stopped-the-levels` | Mixer levels freeze when transport stops | unresolved | feature-follow-up | high | Group into the mixer follow-up as the functional stopped-meter item. Require focused stopped-transport decay/reset evidence, not just screenshots. | Owner says stopped transport leaves mixer levels at their last value. Same mixer surface, but functional. No route or resolution observed. |
| `docs/bugs/20260616-110235-the-behaviour-of-pattern-layer-in-a-cell` | Track Perform pattern layer cells should be directly clickable | unresolved | feature-follow-up | medium | Route later as a bounded Track Perform pattern-layer interaction fix: mini-view cells become explicit click targets instead of whole-card incrementing. | Fresh owner note plus image. Existing performance-layer summaries are terminal/contained in `main`; no active branch, route, or resolution evidence found for this new interaction complaint. |

## Legacy Markdown Outside Folder Scope

These root-level markdown reports are not folder-style bug reports, but they
live under `docs/bugs` and still lack a folder-local `resolution.md` lifecycle.

| path | title | status | scope | priority | routing_hint | evidence |
| --- | --- | --- | --- | --- | --- | --- |
| `docs/bugs/2026-06-10-mixer-ux-review.md` | Mixer UX review | probably-resolved-missing-resolution | process-repair | low | Do not route product work from this legacy review. If cleanup is desired, reconcile the flat report with the resolved `20260611-143027.../resolution.md` evidence. | File status says resolved on `feature/mixer-overhaul` and points to `docs/bugs/20260611-143027-the-mixer-layout-is-a-big-mess-there-are/resolution.md`. Current state records mixer overhaul landed. New June 16 mixer reports are separate follow-up bugs. |
| `docs/bugs/2026-06-10-qa-surface-review.md` | QA surface review residuals | needs-triage | process-repair | low | Do not route as a broad UI sweep. If acted on, first split still-relevant residuals from stale/resolved items, especially old layer-index capture no-op and remaining explainer/pill notes. | Status update marks most P0/P1 findings fixed or superseded, but leaves P0.5 layer-index capture diagnosis plus some P1.9/P1.10 cleanup. Later captures, flat-UI work, and owner bugs supersede much of the surface. |
| `docs/bugs/2026-06-12-qa-capture-review.md` | Tracks edit card height taste call | blocked-on-human | pm-clarification | medium | Wait for the existing product-owner taste call: edit-mode cards should either shrink to content or use reserved space for destination/source info. Recommended default if forced: surface useful source/destination info rather than create a shorter one-off edit-card rhythm. | F2-F4 are resolved in the file and landed at `23619634`; F1 remains explicitly open. `.foreman/attention.md` carries the same tracks-edit card-height question under perform/setup review. |

## Grouping

- Already-routed routing split:
  `20260615-tracks-routing-source-and-mixer-split` belongs to active
  `build/routing-source-mixer-split`. It is evidence/capture-environment
  recovery work now, not a fresh scheduling target.
- Already-routed AU discovery/rescan group:
  `20260616-104317...` and
  `20260616-au-plugin-list-needs-rescan-without-relaunch` belong to active
  `build/au-discovery-rescan`. Acceptance must cover both restart-time list
  completeness and runtime rescan without UI freeze for effects and
  instruments; the latest build-loop decision holds on local CoreAudio/HAL
  machine state.
- Unrouted mixer/channel-strip follow-up group:
  `20260616-104459...`, `20260616-104743...`, `20260616-105006...`,
  `20260616-105141...`, and `20260616-115937...` are one owner-visible mixer
  surface. A single bounded builder pass with exact mixer screenshots plus
  stopped-meter evidence is the smallest honest next action once capacity opens
  or the decider intentionally preempts.
- Track Perform pattern-cell behavior is separate and can wait behind the two
  active high-priority lanes and the mixer functional/polish group.
- Legacy flat markdown reports are mostly stale/resolved bookkeeping, except
  the tracks-edit card-height taste call and a low-priority QA-surface triage
  cleanup if the decider wants to close old report residue.

## Decider Signal

1. Highest-value bug group to route next: mixer/channel-strip follow-up, after
   capacity opens or if the decider intentionally preempts. Ordinary build
   slots are currently full.
2. Bugs that should wait behind active work: fresh mixer/channel-strip and
   Track Perform follow-ups should wait behind active routing-split and AU
   discovery/rescan unless the project explicitly opens or swaps a lane. The
   tracks-edit card-height issue should wait for the existing owner taste call.
3. Bugs that appear already routed or stale: routing split and both AU bugs are
   already routed. The old mixer UX review is probably resolved but lacks
   folder-style closure; the 2026-06-10 QA surface review needs stale-residual
   triage before any product work.
4. Process issue preventing bugs from being acted on: ordinary build capacity
   is fully consumed by `build/routing-source-mixer-split` and
   `build/au-discovery-rescan`. CoreAudio/HAL/window-launch state is blocking
   evidence closure in active lanes. Coordinator CLIs still emit Ruby
   `executable-hooks` / `gem-wrappers` warning noise.

## Checks Run

- Read the claimed request and the central bug-observer prompt/actions.
- Ran Foreman Coordinator `inventory.ts --project /Users/maxwilliams/dev/in-sequence`.
- Ran Foreman Coordinator `build-capacity.ts --project /Users/maxwilliams/dev/in-sequence`.
- Listed unresolved `docs/bugs` folders without `resolution.md` and read each
  unresolved `note.md`.
- Read root-level `docs/bugs/*.md` legacy reports.
- Read prior compact bug intake, compact current-work, feature-readiness,
  holistic status, decision log excerpts, active build-loop summaries,
  `.foreman/attention.md`, and `.foreman/decisions.log.md` excerpts.
- Checked direct branch/worktree state for `feature/routing-source-mixer-split`
  and `feature/au-discovery-rescan`.
- No raw actor transcript scan, product build/test suite, visual capture,
  inbox routing, request lifecycle move, merge, rebase, cleanup,
  product-code edit, process repair, lock clearing, or product-owner question
  was performed.
