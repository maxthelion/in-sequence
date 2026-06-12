# Foreman handoff notes (running under a smaller model)

The mechanism (precheck → triage → dispatch → verify → land → books) is
model-agnostic by design. What changes with a less capable model is how
much JUDGMENT each step can safely carry. Run with
`FOREMAN_AUTONOMY=cautious` and these substitutions:

## What transfers as-is
- precheck.sh decides when to act and which lens runs. Obey its output.
- The gate is mechanical: full suite with the standard skips (currently
  two — see state.md), green TO COMPLETION, before any merge.
- The books (state.md / decisions.log.md / attention.md) and the
  checklists in `checklists/`.
- The regression nets do the hard verification now: gate suite, TSan
  lane, churn stress, render-harness smokes, tick-isolation watchdog,
  invalidation tests. Trust a green net over your own reasoning;
  NEVER weaken, skip-list, or suppress a net to get to green.

## Cautious-mode substitutions
- Triage: small/mechanical fixes → do directly. ANYTHING ambiguous,
  cross-cutting, or judgment-bearing (intent conflicts, behavior
  changes, architecture) → write it to attention.md for Max instead of
  deciding. When unsure whether something is ambiguous, it is.
- Merging: only fast-forward merges of branches whose gate ran green
  on the EXACT tree being merged. If a merge needs conflict
  resolution beyond pbxproj-via-xcodegen, stop and park it.
- Never rewrite tests to match observed behavior. A red test after a
  refactor is a finding for attention.md (precedent: the
  "double-schedule" red was a stale test ONCE and a real bug ZERO
  times — but it took adversarial verification to know which).
- Dispatch briefs: reuse the brief patterns in decisions.log.md
  history. Always include: worktree setup, disk rules, Info.plist
  restore after xcodegen, explicit-path commits, commit incrementally,
  the current skip list, "do not merge to main".

## Standing hazards (verbatim from hard experience)
- xcodegen clobbers Info.plist keys (NSMicrophoneUsageDescription,
  GitBranch) — restore from main and verify after EVERY generate.
- Never remove a worktree or build dir while an app may be running
  from it (check `pgrep -x SequencerAI` + bundle path).
- Never `git add <directory>`; explicit paths only.
- Test runs that stall ~18 min are degraded coreaudiod (machine
  state), not code. Don't kill other processes; note and move on.
- Disk: check `df -h /System/Volumes/Data` before suites; stop under
  1.5Gi. One build lane until the WhatsApp quarantine is deleted.
- Session limits kill agents mid-work: park dirty worktrees, record
  resume notes in state.md, relaunch with continue-the-dirty-work
  briefs (several precedents in the log).

## Mode: POLISH (as of 2026-06-12)
V1 features are essentially built. Bias away from feature slices:
1. Inputs are Max's bug reports (docs/bugs via the 4747 reporter),
   screenshot reviews against docs/ux-canon.md, and net regressions.
2. Prefer many small fix slices over big briefs; one concern per
   branch; land fast.
3. Heartbeat lenses do the proactive finding (QA captures + ux-canon
   review, intent drift, concurrency lane).
4. The multipass pm/build loops are Max's to wind down — do not touch
   their config; just don't route work to them.
5. The red-team harness brief (docs/testing/red-team-harness-brief.md)
   is the next standing-quality investment when capacity allows.
