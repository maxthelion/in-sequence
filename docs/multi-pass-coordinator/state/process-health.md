# Process Health

- updated: 2026-05-23T16:08Z
- request: `.meta/multipass/inbox/claimed/2026-05-23T16-05-58-300Z-process-health-observer-cadence.md`
- loop-local copy: `.meta/multipass/loops/project/observe/process-health.md`
- observation artifact: `.meta/multipass/loops/project/observe/2026-05-23T16-08Z-process-health-observation.md`
- scope: observation only; no inbox messages, decisions, lifecycle changes,
  merge, push, cleanup, product-code edits, or build-loop actions performed.

## Checklist

- [x] Builders/integrators are doing real product work, not only coordination
  bookkeeping.
- [x] Review failures are feeding back into focused rework, refreshed gates, or
  integration disposition.
- [ ] Recent high-context actor runs are stable enough to avoid repeated
  recovery/reconstruction load.
- [ ] Runtime inbox status is low-noise and free of stale terminal-loop or
  blocked-request churn.
- [ ] Deterministic observation scripts cover the state actors repeatedly need.
- [ ] Visual/runtime review evidence is consistently backed by reproducible
  checked-in app-surface and runtime-log tooling.
- [x] Product-owner attention is not being used for agent-detectable process
  problems.

## Observations

| Area | Evidence | Health read |
| --- | --- | --- |
| Product progress | Since the 12:01Z process-health pass, Step Sequencer Phase 2-A reached bounded exact-output acceptance for `26d858e` with architecture/testing/UX/visual evidence scoped to the isolated `UnifiedStepCell` primitive. Clip History Phase 3 committed real visible transfer workflow output at `337aa5c`, with act evidence and testing-sufficient review. Step Sequencer Phase 2-B also attempted real clip-editor wiring and left salvageable dirty implementation material. | The loop is producing product work, not just markdown. Health remains yellow because neither active loop has a currently accepted/showable next workflow output. |
| Review follow-through | Clip History architecture review rejected `337aa5c` because generator-backed occupied pattern slots can bypass inline `Replace`; build-decider routed `.meta/multipass/inbox/pending/2026-05-23T15-01-55-168Z-Clip-History-Phase-3-occupied-slot-Replace-correction.md`. Step Sequencer Phase 2-B failure was oriented as dirty partial work, and build-decider waited for process cleanup instead of duplicating a retry. | Review/rework discipline is still working. The loop is not over-crediting either a committed rejected output or an uncommitted dirty partial diff. |
| Actor reliability | Compact failure evidence since noon includes project work-observer `usage_rate_limit`, Step Sequencer build-orienter `usage_rate_limit`, project log-observer `usage_rate_limit`, Clip History visual-economy `usage_rate_limit`, and Step Sequencer Phase 2-B builder `usage_rate_limit`. | Reliability has worsened from yellow to yellow/red. Recovery is functioning, but too many acceptance-critical actors now fail before final artifacts and force later actors to reconstruct state. |
| Environment/tooling | Direct process check during this pass still shows two long-running orphaned Phase 2-B `xcodebuild` processes, one over 48 minutes and one over 45 minutes. Clip History UX/IA screenshot attempts hung in `xcodebuild`/app-surface tooling; testing review also hit a DerivedData `build.db` lock before serial rerun passed. `inventory.ts` and `build-capacity.ts` still emit Ruby gem-extension warnings before useful output. | The current process bottleneck is tooling/runtime hygiene, not product ambiguity. Hung Xcode work and noisy CLI output are concrete token and resource churn sources. |
| Inbox/resource churn | `scripts/multi-pass/inbox-status.sh` reports `6` pending, `1` claimed, `36` blocked, and `610` done. Active pending work is coherent: Clip History correction, Clip History build-decider cadence, project process-fixer cleanup, project orienter cadence, and Step Sequencer build-orienter cadence. One stale Scene Perform cadence remains isolated under terminal-loop residue. | Primary routing is low-noise, but the blocked pile is growing and terminal-loop residue still exists. Actors that ignore the helper split can still misread stale state. |
| Deterministic visibility | Present helpers include `project-status.sh`, `review-status.sh`, `inbox-status.sh`, and the visual scenario shell entrypoint. Missing helpers remain `pairing-state.sh`, `feature-state.sh`, `merge-status.sh`, `rebase-status.sh`, and `runtime-log-scan.sh`. `app-surfaces.sh` exists but did not produce Clip History screenshots for the exact commit. | Deterministic visibility is still incomplete. The loop repeatedly spends high-context actor time reconstructing pairing, feature, merge, rebase, and runtime facts that should be cheap reads. |
| Visual evidence | Step Sequencer Phase 2-A has a usable rendered PNG for the primitive. Clip History Phase 3 does not have credible rendered modal evidence: UX/IA is `evidence-insufficient`, visual-economy failed before final artifact, and the smallest satisfying evidence is a deterministic scenario that can seed capture history and show entry, empty, source-selected, occupied-Replace, and enabled-save states. | Visual review discipline is correct, but the tooling gap blocks acceptance and burns reviewer time. |
| Evidence packaging | Some acceptance evidence still lives as actor finals rather than normalized loop-local observe artifacts, including architecture reviews. The Clip History visual-economy failure artifact is large and stderr-heavy without a concise final verdict. Review batch lifecycle metadata remains uneven around superseded/failed exact outputs. | Evidence remains interpretable but costly. Later actors can recover, but they must read across durable summaries, loop artifacts, finals, failures, direct git, and process state. |
| Product-owner attention | Current blockers are agent-side: process cleanup for stuck `xcodebuild`, Step Sequencer Phase 2-B continuation after cleanup, Clip History occupied-slot correction, fresh exact-state reviews, rendered modal evidence, helper gaps, CLI warning noise, and evidence normalization. | No product-owner attention is needed. Human attention should remain scoped to actual prototype/product checkpoints. |

## Suspected Causes

- High-context builder and review actors run long enough to hit usage limits
  before writing a final artifact or compact partial checkpoint.
- Xcode and visual-scenario commands are not consistently bounded by timeouts,
  cleanup, per-run DerivedData isolation, and branch/commit attribution.
- State remains scattered across durable summaries, loop artifacts, actor
  finals/failures, inbox status, activity logs, direct git facts, and direct
  process checks because small read-only helpers are missing.
- Visual review requires exact built-surface evidence, but Clip History lacks a
  deterministic scenario that can seed and capture the relevant modal states.
- Runtime-owned stale requests can be hidden from primary views, but there is
  still no supported cleanup/archive path for terminal-loop residue.
- Local Ruby environment warnings pollute otherwise successful coordinator CLI
  output.

## Suggested Repair Shape

- Let the already-pending process-fixer request clean up stuck Phase 2-B
  `xcodebuild` processes before Step Sequencer retries or continues Phase 2-B.
- Tighten actor contracts for heavy builders/reviewers: write compact partial
  evidence before long tests or visual commands, and record exact dirty/commit
  state when a run becomes partial.
- Add bounded Xcode/visual command conventions: explicit timeout, per-run
  DerivedData where useful, cleanup on failure, and app launch commit/branch
  attribution before accepting runtime or screenshot evidence.
- Add or restore small read-only helpers for pairing/build-loop state, feature
  readiness, merge facts, rebase/worktree facts, and runtime-log scans.
- Add a Clip History visual scenario that can seed a generator-source track,
  inject or populate recent capture history, open the transfer sheet, select
  source and destination cells, show occupied-slot `Replace`, and show enabled
  save state.
- Normalize architecture/review finals into loop-local observe artifacts when
  they are acceptance evidence, and add a clear close/supersede convention for
  review batches.
- Keep terminal-loop residue split out of primary inventory/capacity/inbox
  reads until a runtime-owned cleanup command exists.
- Repair or filter Ruby gem-extension warning noise for coordinator CLI
  commands.

## Current Disposition

The loop is product-progressing and review-disciplined, but process health is
yellow/red. Builders are landing or attempting real product slices, and review
failures are becoming bounded rework. The weak point is resource churn:
usage-limit failures, hung `xcodebuild`/visual probes, orphaned build
processes, missing helper scripts, and uneven evidence packaging are forcing
repeated reconstruction. No product-owner attention is needed from this
observation.
