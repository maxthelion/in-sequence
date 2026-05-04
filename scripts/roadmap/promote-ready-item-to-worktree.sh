#!/usr/bin/env bash
# Promote a ready roadmap item into the implementation behaviour-tree loop.
#
# This script does not build the feature. It creates a dedicated git worktree
# and writes a normalized docs/plans/*roadmap-*.md build plan there. The
# original implementation BT can then run inside that worktree with /next-action.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/roadmap/promote-ready-item-to-worktree.sh [--dry-run] [--no-visual-review] [--visual-review-app-name <name>] <item-id>

Creates:
  .worktrees/roadmap-<id>-<slug>/
  branch auto/roadmap-<id>-<slug>
  docs/plans/YYYY-MM-DD-roadmap-<id>-<slug>.md inside the worktree

Then run the implementation loop from the printed worktree:
  cd .worktrees/roadmap-<id>-<slug>
  .claude/hooks/setup-next-action.sh
  /loop /next-action
EOF
}

DRY_RUN=0
VISUAL_REVIEW_MODE="auto"
VISUAL_REVIEW_APP_NAME="${VISUAL_REVIEW_APP_NAME:-}"

while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-visual-review)
      VISUAL_REVIEW_MODE="off"
      shift
      ;;
    --visual-review-app-name)
      VISUAL_REVIEW_APP_NAME="${2:-}"
      if [ -z "$VISUAL_REVIEW_APP_NAME" ]; then
        echo "--visual-review-app-name requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

ITEM_ID="${1:-}"
if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "-h" ] || [ "$ITEM_ID" = "--help" ]; then
  usage
  exit 0
fi

case "$ITEM_ID" in
  ''|*[!0-9]*)
    echo "Item id must be an integer: $ITEM_ID" >&2
    exit 1
    ;;
esac

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO"

ROADMAP_DIR="$REPO/docs/roadmap"
WORKTREE_ROOT="$REPO/.worktrees"

frontmatter_value() {
  local file="$1"
  local key="$2"
  local fallback="${3:-}"

  if [ ! -f "$file" ]; then
    printf '%s\n' "$fallback"
    return
  fi

  local value
  value="$(awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      print
      exit
    }
  ' "$file")"

  if [ -n "$value" ]; then
    printf '%s\n' "$value" | sed 's/^"//; s/"$//'
  else
    printf '%s\n' "$fallback"
  fi
}

feature_dir_for_id() {
  local id="$1"
  local readme
  while IFS= read -r readme; do
    if [ "$(frontmatter_value "$readme" "id" "")" = "$id" ]; then
      dirname "$readme"
      return 0
    fi
  done < <(find "$ROADMAP_DIR" -mindepth 2 -maxdepth 2 -name README.md -type f | sort)
  return 1
}

FEATURE_DIR="$(feature_dir_for_id "$ITEM_ID" || true)"
if [ -z "$FEATURE_DIR" ]; then
  echo "No roadmap item found with id $ITEM_ID" >&2
  exit 1
fi

SLUG="$(basename "$FEATURE_DIR")"
TITLE="$(frontmatter_value "$FEATURE_DIR/README.md" "title" "$SLUG")"
STAGE="$(frontmatter_value "$FEATURE_DIR/README.md" "stage" "unknown")"

for required in "implementation-handoff.md" "spec.md" "plan.md"; do
  if [ ! -s "$FEATURE_DIR/$required" ]; then
    echo "Roadmap item $ITEM_ID ($TITLE) is not ready: missing $FEATURE_DIR/$required" >&2
    exit 1
  fi
done

if [ "$STAGE" != "ready-for-build-queue" ]; then
  echo "Roadmap item $ITEM_ID ($TITLE) has stage '$STAGE', expected 'ready-for-build-queue'." >&2
  echo "Refusing to promote until the PM selector has marked it ready." >&2
  exit 1
fi

BRANCH="auto/roadmap-${ITEM_ID}-${SLUG}"
WORKTREE="$WORKTREE_ROOT/roadmap-${ITEM_ID}-${SLUG}"
PLAN_FILE="docs/plans/$(date -u +"%Y-%m-%d")-roadmap-${ITEM_ID}-${SLUG}.md"

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "Branch already exists: $BRANCH" >&2
  exit 1
fi

if [ -e "$WORKTREE" ]; then
  echo "Worktree path already exists: $WORKTREE" >&2
  exit 1
fi

TASKS=()
while IFS= read -r task; do
  [ -n "$task" ] && TASKS+=("$task")
done < <(awk '
  function flush_phase() {
    if (phase != "" && phase_has_child == 0) {
      print phase
    }
  }
  /^### / {
    flush_phase()
    phase = substr($0, 5)
    phase_has_child = 0
    next
  }
  /^#### / {
    phase_has_child = 1
    print substr($0, 6)
    next
  }
  END {
    flush_phase()
  }
' "$FEATURE_DIR/plan.md")

if [ "${#TASKS[@]}" -eq 0 ]; then
  echo "Could not extract build tasks from $FEATURE_DIR/plan.md" >&2
  exit 1
fi

selected_prototype() {
  local approval="$FEATURE_DIR/prototype-approval.md"
  local ux="$FEATURE_DIR/ux-review.md"
  local value=""
  value="$(frontmatter_value "$approval" "prototype" "")"
  if [ -z "$value" ]; then
    value="$(frontmatter_value "$ux" "selected_prototype" "")"
  fi
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi
  find "$FEATURE_DIR/prototypes" -maxdepth 1 -type f -name '*.html' 2>/dev/null | sort | head -1 | sed "s#^$FEATURE_DIR/##"
}

SHOULD_VISUAL_REVIEW=0
PROTOTYPE_REF="$(selected_prototype || true)"
if [ "$VISUAL_REVIEW_MODE" != "off" ]; then
  if [ -s "$FEATURE_DIR/prototype-approval.md" ] || [ -n "$PROTOTYPE_REF" ]; then
    SHOULD_VISUAL_REVIEW=1
  fi
fi

echo "Roadmap item: $ITEM_ID $TITLE"
echo "Source:       docs/roadmap/$SLUG/"
echo "Worktree:    $WORKTREE"
echo "Branch:      $BRANCH"
echo "Build plan:  $PLAN_FILE"
echo "Tasks:       ${#TASKS[@]}"
if [ "$SHOULD_VISUAL_REVIEW" -eq 1 ]; then
  echo "Visual gate: yes (${VISUAL_REVIEW_APP_NAME:-APP_NAME to be supplied})"
else
  echo "Visual gate: no"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "Dry run only. No worktree or files created."
  exit 0
fi

mkdir -p "$WORKTREE_ROOT"
git worktree add -b "$BRANCH" "$WORKTREE" HEAD

mkdir -p "$WORKTREE/docs/plans"
{
  echo "# Roadmap Build Plan: $TITLE"
  echo
  echo "**Status:** Active."
  echo "**Roadmap item:** $ITEM_ID"
  echo "**Roadmap source:** \`docs/roadmap/$SLUG/\`"
  echo
  echo "This plan was generated by \`scripts/roadmap/promote-ready-item-to-worktree.sh\`."
  echo "Run it only inside the dedicated worktree for \`$BRANCH\`."
  echo
  echo "## Architecture"
  echo
  echo "Use \`docs/roadmap/$SLUG/implementation-handoff.md\` as the authoritative entry point."
  echo "Follow the guardrails in \`docs/roadmap/$SLUG/architecture.md\` and the accepted decisions in \`docs/roadmap/$SLUG/architecture-review.md\`."
  echo "Do not re-litigate PM decisions in implementation; if a task exposes a missing product decision, write a note to \`.claude/state/inbox/\` and stop."
  echo
  echo "## Environment"
  echo
  echo "Build in this worktree on branch \`$BRANCH\`."
  echo "Use the normal implementation behaviour tree: \`.claude/hooks/setup-next-action.sh\` then \`/next-action\` or \`/loop /next-action\`."
  echo "Keep implementation slices narrow. Each task below maps back to a section in \`docs/roadmap/$SLUG/plan.md\`."
  echo

  task_number=1
  for task in "${TASKS[@]}"; do
    echo "## Task $task_number: $task"
    echo
    echo "- [ ] Execute the \`$task\` section from \`docs/roadmap/$SLUG/plan.md\`, using \`docs/roadmap/$SLUG/implementation-handoff.md\` for acceptance criteria, non-goals, source locations, gates, and test expectations."
    echo
    task_number=$((task_number + 1))
  done
} > "$WORKTREE/$PLAN_FILE"

if [ "$SHOULD_VISUAL_REVIEW" -eq 1 ]; then
  mkdir -p "$WORKTREE/.peekaboo-loop"
  {
    echo "# Visual review recipe generated by pm-loop promotion."
    echo
    echo "SCENARIO_NAME=\"roadmap-${ITEM_ID}-${SLUG}\""
    echo "APP_NAME=\"\${VISUAL_REVIEW_APP_NAME:-$VISUAL_REVIEW_APP_NAME}\""
    echo "PEEKABOO_BIN=\"\${PEEKABOO_BIN:-peekaboo}\""
    echo "OUTPUT_ROOT=\".claude/state/visual-review\""
    echo "APP_PATH_COMMAND=\"scripts/open-latest-build.sh --print\""
    echo "PRODUCT_PATHS=\"Sources Tests SequencerAI.xcodeproj Package.swift\""
    echo "REFERENCE_PROTOTYPE=\"docs/roadmap/$SLUG/${PROTOTYPE_REF:-prototypes}\""
    echo "REFERENCE_REVIEW=\"docs/roadmap/$SLUG/ux-review.md\""
    echo "BUILD_CONTEXT=\"Roadmap item $ITEM_ID: $TITLE. Compare the built UI against docs/roadmap/$SLUG/implementation-handoff.md, spec.md, prototype-approval.md, ux-review.md, and the selected prototype. The visual reviewer should decide whether the user should see the build before ready-for-user is signalled.\""
    echo "PRE_CAPTURE_SCRIPT=\"\""
  } > "$WORKTREE/.peekaboo-loop/visual-review.env"
fi

git -C "$WORKTREE" add "$PLAN_FILE"
if [ "$SHOULD_VISUAL_REVIEW" -eq 1 ]; then
  git -C "$WORKTREE" add .peekaboo-loop/visual-review.env
fi
git -C "$WORKTREE" commit -m "plan(roadmap): promote item $ITEM_ID $SLUG"

git -C "$WORKTREE" status --short
"$WORKTREE/.claude/hooks/setup-next-action.sh" >/dev/null

echo
echo "Promoted roadmap item $ITEM_ID to implementation worktree."
if [ "$SHOULD_VISUAL_REVIEW" -eq 1 ]; then
  echo "Visual review recipe written to .peekaboo-loop/visual-review.env."
  echo "If APP_NAME is blank, install peekaboo-loop and set VISUAL_REVIEW_APP_NAME or edit the recipe before the build can signal ready."
fi
echo "Next:"
echo "  cd $WORKTREE"
echo "  cat .claude/state/next-action.md"
echo "  /loop /next-action"
