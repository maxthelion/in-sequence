# Post-Merge Feedback: Mixer Tab Hang

Date: 2026-06-06
Area: Mixer / Mixer Busses / main navigation
Source: product-owner review of the app on main

## Feedback

Clicking the Mixer button appears to hang the app. The application does not
quit by itself; it becomes unresponsive enough that it has to be force quit.

This may be a regression of an issue seen previously, but the exact reviewed
build is unclear from the app UI.

## Evidence Collected

`scripts/multi-pass/runtime-log-scan.sh 60` was run after the report.

- No recent `SequencerAI` crash report was found in
  `~/Library/Logs/DiagnosticReports`.
- That fits a hang or force-quit rather than a normal crash report.
- Recent launch metadata includes both unattributed launches and one attributed
  launch:
  - `gitCommit=4ae5889`
  - `gitBranch=main`
  - bundle build still reported as `1`
- Latest build-attribution manifest before this report:
  `.meta/multipass/runtime/build-attribution/20260606174401.json`
  says:
  - attribution id: `4ae5889-dirty-20260606174401`
  - commit: `4ae5889`
  - branch: `main`
  - dirty: `dirty`
  - built at: `2026-06-06T17:44:35Z`

## Desired Handling

Treat this as a runtime/product regression that needs a reproducible route:

1. Open a stamped main build.
2. Record visible build identity.
3. Click Mixer from the main navigation.
4. If the app hangs, capture a sample/spindump before force quit if possible.
5. Route the fix to the appropriate loop based on whether the hang is tied to
   mixer-busses, mixer-main-out, send effects, or broader mixer construction.

The absence of a crash report should not downgrade the issue. A UI hang during
top-level navigation is a serious review blocker.

