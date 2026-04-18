#!/usr/bin/env bash
# Evaluates the behaviour tree deterministically and writes
# .claude/state/next-action.md describing what the next agent should do.
#
# This is the cheap side of the /next-action split: no LLM required.
# It's run either by a SessionStart hook, the /setup slash command, or
# a /loop wrapper before every iteration.
#
# Reference: https://github.com/maxthelion/shoe-makers (same pattern).

set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO"

STATE="$REPO/.claude/state"
OUT="$STATE/next-action.md"

mkdir -p "$STATE" "$STATE/inbox" "$STATE/review-queue" "$STATE/insights"

# --------- Helpers -----------------------------------------------------------

emit() {
  # Atomic write: populate a tempfile, then rename over $OUT. A concurrent
  # reader of next-action.md either sees the previous complete version or the
  # new complete version — never a truncated in-progress one. `mv` within the
  # same filesystem is atomic on POSIX.
  local tmp="$OUT.tmp.$$"
  {
    echo "# Next Action"
    echo
    echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Repo HEAD: $(git rev-parse --short HEAD)"
    echo "Branch:    $(git rev-parse --abbrev-ref HEAD)"
    echo
    echo "## Action: $1"
    echo
    shift
    printf '%s\n' "$@"
    echo
    echo "---"
    echo
    echo "_Invoke \`/next-action\` to execute. The skill reads this file and dispatches the appropriate subagent._"
  } > "$tmp"
  mv -f "$tmp" "$OUT"
}

# --------- Tree evaluation (selector: first match wins) ----------------------

# [1a] Tests failing?
LAST_TESTS_SHA="$(cat "$STATE/last-tests-sha" 2>/dev/null || echo '')"
HEAD_SHA="$(git rev-parse HEAD)"
if [ "$LAST_TESTS_SHA" != "$HEAD_SHA" ]; then
  # Tests haven't been verified at this SHA yet — need to run them.
  # We don't run the tests from this script (too slow for a setup pass);
  # we just surface "verify tests" as the next action.
  emit "verify-tests" \
    "Tests have not been verified at \`$HEAD_SHA\`." \
    "Run: \`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' test\`" \
    "On pass, update \`.claude/state/last-tests-sha\` with the HEAD SHA." \
    "On fail, the next setup pass will route to \`fix-tests\` with the failing output."
  exit 0
fi

# [1a cont] Did the last test run fail? Check for a saved failure report.
if [ -f "$STATE/last-tests-failure.md" ]; then
  emit "fix-tests" \
    "Tests are failing. Failure details at \`.claude/state/last-tests-failure.md\`." \
    "Dispatch an implementer subagent with the failing test output. Scope: make tests green without changing contracts." \
    "On fix, delete \`.claude/state/last-tests-failure.md\` and update \`last-tests-sha\`."
  exit 0
fi

# [1b] Unresolved adversarial critiques?
CRITIQUE_COUNT=$(find "$STATE/review-queue" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$CRITIQUE_COUNT" -gt 0 ]; then
  # Deterministic "oldest" by lexicographic filename, not mtime (which is
  # checkout-time on a fresh clone and gives non-deterministic BT behaviour).
  OLDEST="$(find "$STATE/review-queue" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort | head -1)"
  emit "fix-critique" \
    "There are $CRITIQUE_COUNT outstanding adversarial critique(s) in \`.claude/state/review-queue/\`." \
    "Oldest: \`$(basename "$OLDEST")\`" \
    "Dispatch an implementer subagent with that critique file's contents." \
    "On fix, delete the critique file and commit."
  exit 0
fi

# [1c] Partial work to resume?
if [ -f "$STATE/partial-work.md" ]; then
  emit "continue-partial-work" \
    "An agent ran out of time mid-task. Handoff details at \`.claude/state/partial-work.md\`." \
    "Dispatch an implementer subagent with the handoff file; pick up exactly where the previous agent left off." \
    "On completion, delete the handoff file and commit."
  exit 0
fi

# [1d] Unreviewed commits since last adversarial review?
LAST_REVIEW_SHA="$(cat "$STATE/last-review-sha" 2>/dev/null || echo '')"
if [ -z "$LAST_REVIEW_SHA" ]; then
  # Never reviewed — use latest tag or initial commit as the base.
  LAST_REVIEW_SHA="$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"
fi
UNREVIEWED=$(git rev-list --count "$LAST_REVIEW_SHA..HEAD" 2>/dev/null || echo '0')
if [ "$UNREVIEWED" -gt 0 ]; then
  emit "adversarial-review" \
    "$UNREVIEWED commit(s) since last adversarial review (\`$LAST_REVIEW_SHA..HEAD\`)." \
    "Invoke the \`adversarial-review\` skill against this diff." \
    "For each finding emitted, write one file to \`.claude/state/review-queue/\` (name: severity-short-slug.md)." \
    "Update \`.claude/state/last-review-sha\` to the current HEAD SHA."
  exit 0
fi

# [1e] Inbox messages from user?
INBOX_COUNT=$(find "$STATE/inbox" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$INBOX_COUNT" -gt 0 ]; then
  # Deterministic oldest — see rationale above.
  OLDEST="$(find "$STATE/inbox" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort | head -1)"
  emit "handle-inbox" \
    "There are $INBOX_COUNT inbox message(s). Oldest: \`$(basename "$OLDEST")\`." \
    "Read the file and act: the message may be a redirect, a new candidate, a plan edit, or a manual instruction." \
    "On completion, move the file to \`.claude/state/inbox/archive/\`."
  exit 0
fi

# [2a] Open work-item?
if [ -f "$STATE/work-item.md" ]; then
  emit "execute-work-item" \
    "Active work-item present at \`.claude/state/work-item.md\`." \
    "Dispatch an implementer subagent via \`superpowers:subagent-driven-development\`." \
    "On DONE: commit, delete the work-item, let the next setup pass route to adversarial-review."
  exit 0
fi

# [2b] Candidates queued?
if [ -f "$STATE/candidates.md" ]; then
  emit "prioritise" \
    "Candidates queued at \`.claude/state/candidates.md\`." \
    "Read candidates + the current code-review checklist at \`wiki/pages/code-review-checklist.md\`." \
    "Pick one. Write a detailed work-item to \`.claude/state/work-item.md\` with: the goal, relevant code paths, relevant tests, the acceptance criterion, the file-size check." \
    "Annotate the chosen candidate in \`candidates.md\` as selected."
  exit 0
fi

# [2c] Plan with unfinished tasks?
ACTIVE_PLAN=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if ! grep -q "Status:.*Completed" "$f" 2>/dev/null; then
    ACTIVE_PLAN="$f"; break
  fi
done < <(find docs/plans -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
if [ -n "$ACTIVE_PLAN" ]; then
  # Find the first unticked checkbox.
  UNTICKED=$(grep -nE '^[[:space:]]*- \[ \]' "$ACTIVE_PLAN" 2>/dev/null | head -1 || true)
  if [ -n "$UNTICKED" ]; then
    emit "promote-plan-task-to-work-item" \
      "Active plan: \`$ACTIVE_PLAN\`" \
      "First unticked step: $UNTICKED" \
      "Extract the enclosing Task section (\`## Task N: …\` through the end of its last step)." \
      "Write it as \`.claude/state/work-item.md\` with the plan's Architecture + Environment note as preamble." \
      "The next setup pass will route to execute-work-item."
    exit 0
  fi
fi

# [2d] No active plan but unfinished sub-specs in the north-star?
SPEC_FILE="$(find docs/specs -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort | tail -1)"
if [ -n "$SPEC_FILE" ] && [ -z "$ACTIVE_PLAN" ]; then
  emit "write-next-plan" \
    "No active plan. Unfinished sub-specs may remain in \`$SPEC_FILE\`'s Decomposition section." \
    "Read the spec's Decomposition section; find the next sub-spec that has no corresponding file under \`docs/plans/\`." \
    "Invoke \`superpowers:writing-plans\` to produce its plan file."
  exit 0
fi

# [3] Exploration fallthrough
emit "explore" \
  "All reactive conditions clear. No active plan or work-item." \
  "Run invariant-drift check (\`octowiki-invariants\`): what is specified but not implemented? implemented but not tested? implemented but not specified?" \
  "Run \`octoclean\` code-smell analysis if installed." \
  "Write findings as a ranked \`.claude/state/candidates.md\`." \
  "The next setup pass will route to prioritise."
