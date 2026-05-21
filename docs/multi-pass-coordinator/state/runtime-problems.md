# Runtime Problems

- updated: 2026-05-21T06:34:20Z
- request: `.meta/multipass/inbox/claimed/2026-05-21T05-56-33-791Z-log-observer-cadence.md`
- scan window: 180 minutes
- scan note: project-local `scripts/multi-pass/runtime-log-scan.sh` is absent
  on current `main`; this pass used the same crash-report and unified-log
  checks from the prior scan script content found in git history.

## Current App Runtime Scan

No recent `SequencerAI*.ips` crash reports were visible under
`~/Library/Logs/DiagnosticReports`, and no matching `SequencerAI` unified-log
error, fatal, exception, crash, abort, or commit/branch launch lines were
visible to the current user in the scan window.

## Problems

| Observed time | Source log/report path | App commit or branch | Crash/error signature | Likely user-facing action affected | Severity | Routing suggestion | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-21T06:13:58Z | `.meta/multipass/state/actor-failures.md`; `.meta/multipass/runs/actors/builder/2026-05-21T06-05-30-227Z-mixer-busses-UI-finish.failure.md` | Build loop `build/mixer-busses`; branch `auto/roadmap-5-mixer-busses-ui-finish`; later completed at `6622bc9` | Actor runtime failure: builder run ended without final artifact; signal `SIGTERM`; no app crash report or app commit metadata in the failure evidence | Build-loop progress and review scheduling for Mixer Busses UI, not an end-user app action | Medium | Already routed by build decider to a builder continuation; no new orienter note from this scan | Handled by `.meta/multipass/runs/actors/builder/2026-05-21T06-16-43-139Z-mixer-busses-builder-continuation-after-missing-final.final.md`; keep normal post-build review gates |

## Evidence Risk

- The app runtime scan only covers logs visible to the current macOS user and
  the 180-minute window.
- No app crash/log finding contained fresh commit or branch metadata. Do not
  infer an app regression source without a reproduced build that logs
  `gitCommit` and `gitBranch` on launch.
