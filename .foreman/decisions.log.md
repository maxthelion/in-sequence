# Decisions log

2026-06-11 12:00 | Foreman mechanism created; this session served as trial tick | .foreman/
2026-06-11 12:00 | UX feedback canonized for observer use | docs/ux-canon.md
2026-06-11 10:20 | Merged feature/drum-kits-and-templates to main on Max's approval; feature-merge gate green (1298 tests post-merge) | merge commit + e35437e
2026-06-11 10:20 | Purged accidentally-committed build-dd derived data; build-dd/ now gitignored | e35437e
2026-06-11 12:23 | Foreman tick: 2 feedback resolutions (mixer-hang, fill-preview); bug triage deferred (interactive session active) | docs/roadmap/*/feedback
2026-06-11 12:45 | Intents processed to roadmap 28/29; master render shipped; 9 feedback resolutions | 2dd2cb5c +
2026-06-11 12:45 | Dispatched library-pools and ux-bug-sweep build agents | .worktrees/
2026-06-11 13:30 | Merged feature/ux-bug-sweep to main (9/9 bug reports resolved); post-merge suite green bar one TickClock wall-clock flake (passes isolated, rerun verified) | 158bf031
2026-06-11 13:35 | Merged main into feature/library-pools; LibraryWorkspaceView conflict resolved toward the branch's real library page (main side was the placeholder + showsHeader tweak, superseded); pbxproj via xcodegen; Info.plist keys restored from main | 82ba0289
2026-06-11 14:00 | Merged feature/library-pools to main (fast-forward to 82ba0289; gate suite green on the identical commit in the worktree — evidence inherited, exact tree match). Recordings persist as library assets, two-level Library page, pool-first creation flows, QA rows 40-42 | 82ba0289
2026-06-11 14:15 | Verified intent drift real for step-sequencer track-source-gap (isSelected:false + inspector sheet both still on main) and that clip-history loop is complete (feedback foreman-owned); dispatched build agents feature/track-source-step-grid and feature/clip-history-corrections | docs/roadmap/*/feedback
2026-06-11 14:15 | Mixer overhaul slice (2026-06-10-mixer-ux-review + roadmap 29 channel levels) queued for next free build slot — two concurrent agent builds is the machine's comfortable ceiling | docs/bugs/2026-06-10-mixer-ux-review.md
2026-06-11 14:35 | Both build agents (track-source-step-grid, clip-history-corrections) died on the subscription session limit (resets 15:10); dirty uncommitted partial work parked in their worktrees, zero commits. No new dispatches this tick — they would hit the same limit. Resume at next cron tick (15:23) with continue-the-dirty-work briefs | .worktrees/
2026-06-11 14:35 | Five new bug reports from Max (14:20-14:54: flatter UI, mixer mess, bar labels, 4-rotaries-per-row, add-track cell height) queued; mixer report folds into the queued mixer slice, rest look like one flatten/density sweep | docs/bugs/
2026-06-11 15:55 | Verified Codex interim work with full suite (green) and landed it: BuildIdentity in top bar/logs, master unity pass-through, sample-accurate voice starts, master render tests. Build-identity feedback resolution written; flagged multipass observability loop to reconcile its parallel partial work | e56c5f75
2026-06-11 15:55 | Resumed both rate-limit-killed agents with continue-the-dirty-work briefs (commit incrementally). Max's five afternoon bugs triaged into three queued slices: small-UI sweep (143510+144448+145433), mixer overhaul (143027 + 06-10 review + roadmap 29; his pan-below-volume ruling overrides the rotary-pan idea), flat-UI try-it variant branch (142049, no merge without his review) | docs/bugs/
