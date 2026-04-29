# Observability From Application Logs Notes

## Raw Intent

The user wants a running script that watches application logs and creates issues from them. Ideally each issue knows which commit likely introduced it, so a sweeper agent can fix the problem or leave it for the active worker if it belongs to current in-flight work.

## Clarified Concern

The project needs an observability loop for runtime problems found outside the test suite. The loop should convert log evidence into actionable work without creating noisy duplicates or routing issues to the wrong agent.

## Initial Logic Sketch

The feature is not just "grep logs and file issues." It needs a deterministic pipeline with careful ownership rules.

Potential flow:

1. Collect application logs from a known source.
2. Parse logs into structured events: timestamp, severity, subsystem, category, message, stack trace, project/document context if available, and app/build metadata.
3. Fingerprint events so repeated occurrences collapse into one issue instead of creating duplicates.
4. Attach provenance: app version, git commit SHA, branch, build timestamp, dirty-tree status if available, and runtime environment.
5. Decide whether an event is new, already known, regressed, resolved, or too noisy.
6. Create or update an issue only when the signal passes the threshold.
7. Route the issue:
   - If it likely came from the active worker's unmerged commit range, assign or leave it to that worker.
   - If it appears on main or a stable branch, send it to a sweeper queue.
   - If provenance is ambiguous, mark it for triage rather than guessing.

## Commit Attribution Questions

Commit attribution probably needs more than the log line itself.

Options to explore:

- Embed `git rev-parse HEAD` or a build-generated commit SHA in the app at build time.
- Include branch name and dirty status in debug builds.
- Include app version/build number for packaged builds.
- Capture first-seen commit by comparing the current log fingerprint against a local issue database.
- Use a bisect-style workflow only for repeatable crashes or deterministic log events.

Likely rule: the script can confidently say "observed in commit X" if the app reports build metadata. It should only say "introduced by commit X" when it has historical evidence that the fingerprint was absent before X and present after X.

## Issue Creation Rules To Consider

- Do not create issues for every warning by default.
- Collapse repeated events by fingerprint.
- Escalate severity for crashes, audio engine failures, data loss risk, MIDI routing failure, persistence failure, and repeated UI exceptions.
- Keep a suppression list for known benign logs.
- Keep issue state local at first, then optionally bridge to Linear or GitHub later.
- Include reproduction hints, recent user action if available, and a compact log excerpt.
- Avoid leaking user file paths or private sample names unless explicitly allowed.

## Open PM Questions

- Which log source should be authoritative: macOS unified logging, app-owned log files, test logs, crash reports, or a combined collector?
- What counts as an issue versus an observation?
- Where should generated issues live initially: `docs/roadmap`, `.claude/state`, GitHub, Linear, or a local queue?
- How should the active-worker handoff be detected?
- Should this run continuously, at app exit, on a timer, or as part of the behaviour-tree heartbeat?
- What privacy rules should apply to captured logs?
