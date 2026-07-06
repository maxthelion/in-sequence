# Goal: Preserve Useful Dirty State

Status: active
Created: 2026-07-06
Checkout: `/Users/maxwilliams/dev/in-sequence`

## Objective

Turn the wider dirty state into useful, reviewable history without committing
runtime noise. Preserve intake evidence, process/documentation updates, and real
UI/source work in logical batches. Keep generated coordinator state and stale
local visual-review artifacts out unless deliberately captured.

## Dirty-State Buckets

### Preserve

- Bug intake evidence under `docs/bugs/20260705-*` and `docs/bugs/20260706-*`.
- Bug-reporter/R2 workflow documentation and visual-capture script updates:
  `AGENTS.md`, `CLAUDE.md`, `wiki/pages/app-command-channel.md`,
  `scripts/visual-scenarios/peekaboo-common.sh`,
  `scripts/visual-scenarios/peekaboo-no-remote.sh`,
  `scripts/visual-scenarios/auto-capture-watch.sh`,
  `scripts/visual-scenarios/r2-archive-local.sh`,
  `scripts/visual-scenarios/r2-captures.mjs`.
- Real UI/source work, split by feature:
  - Track navigator right-click selection, copy/paste, and duplicate-track
    plumbing.
  - Phrase layer cell context actions and selection cleanup.
  - Drum-kit/add-group empty-kit and add-part flow.
  - Scene/mixer/kit visual polish and consistent workspace inset.
- Roadmap/goal docs that explain the above work:
  `docs/roadmap/july-5-ui-feedback-batch/`,
  `docs/roadmap/drum-kit-matrix-sound-prep/`,
  `docs/roadmap/track-phrase-perform-interaction-prep/`,
  `docs/plans/2026-07-06-limited-color-ui.md`,
  `docs/roadmap/limited-color-ui/`.

### Do Not Commit Blindly

- `.meta/multipass/state/*` and `.meta/multipass/config/*`: live coordinator
  state, useful operationally but too noisy for source history unless a separate
  Foreman-state snapshot is explicitly desired.
- `.meta/multipass/visual-review/codex/july4-ui-feedback-batch/*` deletions:
  likely old local evidence cleanup, but large and separate from source work.
- `.meta/multipass/visual-review/manifests/*` currently tied to old commit
  `9c1744ba`; refresh after clean captures before committing any manifest.

## Execution Plan

1. Commit this goal document.
2. Commit bug intake evidence as docs-only.
3. Commit bug-reporter/R2 capture workflow docs and scripts.
4. Validate source/UI dirty work with:
   - `git diff --check` over staged source files.
   - `scripts/diagnostics/ux-canon-lint.sh`.
   - A focused `xcodebuild` build or relevant tests.
5. Commit source/UI work in coherent batches:
   - track navigator interactions;
   - phrase layer interactions;
   - drum-kit/add-group flow;
   - scene/mixer/padding visual polish.
6. Run a fresh capture against the current clean commit:

   ```sh
   PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/qa-$USER" \
     scripts/visual-scenarios/qa-surface-coverage.sh

   bug-reporter absorb-captures "$TMPDIR/in-sequence-captures/qa-$USER" \
     --project in-sequence \
     --source qa-surface-coverage
   ```

7. Commit refreshed capture metadata only if it is generated for the current
   clean commit and belongs in source history.
8. Leave `.meta/multipass/state/*` and stale local visual-review deletions
   uncommitted unless separately requested.

## Completion Criteria

- Useful docs/evidence/process/source changes are committed in logical batches.
- Source commits pass the relevant lint/build/test checks.
- Captures are absorbed for the clean current commit, or any capture blocker is
  recorded clearly.
- Remaining dirty state is only known-noisy runtime/generated state or explicitly
  deferred work.
