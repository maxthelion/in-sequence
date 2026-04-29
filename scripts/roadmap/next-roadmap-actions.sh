#!/usr/bin/env bash
# Experimental deterministic roadmap selector.
#
# This is the project-management counterpart to the implementation behaviour
# tree. It does not dispatch agents and it does not build anything. It reads
# docs/roadmap/<feature>/ and reports the likely next planning action for each
# feature area from the artifacts already present.

set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO"

ROADMAP_DIR="$REPO/docs/roadmap"
OUT="$ROADMAP_DIR/next-actions.md"

if [ ! -d "$ROADMAP_DIR" ]; then
  echo "Missing roadmap directory: $ROADMAP_DIR" >&2
  exit 1
fi

has_content_file() {
  local file="$1"
  [ -s "$file" ]
}

has_prototype() {
  local dir="$1"
  [ -d "$dir/prototypes" ] || return 1
  find "$dir/prototypes" -maxdepth 1 -type f \( -name '*.html' -o -name '*.md' -o -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) | grep -q .
}

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

feature_meta() {
  local dir="$1"
  local key="$2"
  local fallback="${3:-}"
  frontmatter_value "$dir/README.md" "$key" "$fallback"
}

read_title() {
  local dir="$1"
  local readme="$dir/README.md"
  local title
  title="$(feature_meta "$dir" "title" "")"
  if [ -n "$title" ]; then
    printf '%s\n' "$title"
  elif [ -f "$readme" ]; then
    sed -n 's/^# //p' "$readme" | head -1
  else
    basename "$dir"
  fi
}

roadmap_dirs() {
  # Backlog order lives in docs/roadmap/README.md. Fall back to the working
  # roadmap doc's inventory, then lexicographic directory order.
  local index="$ROADMAP_DIR/README.md"
  local inventory="$REPO/docs/working-through-a-roadmap.md"
  local listed=""

  if [ -f "$index" ]; then
    listed="$(sed -n 's/^- \(**[0-9][0-9]*\*\* \)\{0,1\}\[[^]]*\](\([^)]*\/\))$/\2/p' "$index" | while IFS= read -r rel; do
      rel="${rel%/}"
      if [ -d "$ROADMAP_DIR/$rel" ]; then
        printf '%s\n' "$ROADMAP_DIR/$rel"
      fi
    done)"
  fi

  if [ -z "$listed" ] && [ -f "$inventory" ]; then
    listed="$(sed -n 's/^- \*\*Feature area:\*\* //p' "$inventory" | while IFS= read -r title; do
      slug="$(printf '%s\n' "$title" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/&/and/g; s/[^a-z0-9]/-/g; s/-\{1,\}/-/g; s/^-//; s/-$//')"
      if [ -d "$ROADMAP_DIR/$slug" ]; then
        printf '%s\n' "$ROADMAP_DIR/$slug"
      fi
    done)"
  fi

  {
    printf '%s\n' "$listed"
    find "$ROADMAP_DIR" -mindepth 1 -maxdepth 1 -type d | sort
  } | awk 'NF && !seen[$0]++'
}

classify_feature() {
  local dir="$1"
  local next_action=""
  local reason=""
  local output_hint=""
  local status
  local blocked_by

  status="$(feature_meta "$dir" "status" "unknown")"
  blocked_by="$(feature_meta "$dir" "blocked_by" "[]")"

  if [ "$status" = "blocked" ] || { [ -n "$blocked_by" ] && [ "$blocked_by" != "[]" ]; } || has_content_file "$dir/open-questions.md"; then
    next_action="blocked"
    reason="Status is \`$status\`, blocked_by is \`$blocked_by\`, or \`open-questions.md\` exists."
    output_hint="Answer the open questions or resolve the blocker before advancing this item."
    printf '%s\t%s\t%s\n' "$next_action" "$reason" "$output_hint"
    return
  fi

  if ! has_content_file "$dir/notes.md"; then
    next_action="clarify-feature"
    reason="No \`notes.md\` yet."
    output_hint="Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints."
  elif ! has_content_file "$dir/user-stories.md"; then
    next_action="draft-user-stories"
    reason="\`notes.md\` exists, but \`user-stories.md\` is missing."
    output_hint="Run a background PM pass. Write \`user-stories.md\`, or create \`open-questions.md\` and mark the feature blocked if the notes are too thin."
  elif ! has_content_file "$dir/existing-state.md"; then
    next_action="inspect-existing-state"
    reason="User stories exist, but \`existing-state.md\` is missing."
    output_hint="Inspect code, docs, tests, screenshots, and prototypes; report model/UI gaps with file references."
  elif ! has_prototype "$dir"; then
    next_action="build-prototypes"
    reason="Existing-state report exists, but no prototype artifact was found in \`prototypes/\`."
    output_hint="Create focused Balsamiq-style HTML prototypes under this feature directory."
  elif ! has_content_file "$dir/ux-review.md"; then
    next_action="review-prototypes"
    reason="Prototype artifacts exist, but \`ux-review.md\` is missing."
    output_hint="Review variants against the UX checklist and choose or reject a direction."
  elif ! has_content_file "$dir/architecture.md"; then
    next_action="write-architecture"
    reason="UX review exists, but \`architecture.md\` is missing."
    output_hint="Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks."
  elif ! has_content_file "$dir/architecture-review.md"; then
    next_action="review-architecture"
    reason="Architecture guardrails exist, but \`architecture-review.md\` is missing."
    output_hint="Review the architecture summary before spec: data/runtime shape, transient versus persisted state, guardrails, and open questions."
  elif ! has_content_file "$dir/spec.md"; then
    next_action="write-spec"
    reason="Architecture review exists, but \`spec.md\` is missing."
    output_hint="Write the feature specification from the selected prototype direction and reviewed architecture guardrails."
  elif ! has_content_file "$dir/plan.md"; then
    next_action="write-plan"
    reason="Spec exists, but \`plan.md\` is missing."
    output_hint="Write the implementation plan without starting production work."
  elif ! has_content_file "$dir/implementation-handoff.md"; then
    next_action="write-implementation-handoff"
    reason="Plan exists, but \`implementation-handoff.md\` is missing."
    output_hint="Bundle the PM artifacts into a build-loop handoff that links authoritative context, guardrails, spec, plan, non-goals, and open questions."
  else
    next_action="ready-for-build-queue"
    reason="Planning artifacts are present."
    output_hint="Promote the implementation handoff into the normal build queue when the user chooses."
  fi

  printf '%s\t%s\t%s\n' "$next_action" "$reason" "$output_hint"
}

action_agent() {
  local action="$1"

  case "$action" in
    clarify-feature|blocked|review-prototypes|review-architecture)
      printf '%s\n' "user"
      ;;
    ready-for-build-queue)
      printf '%s\n' "pm"
      ;;
    *)
      printf '%s\n' "pm-assistant"
      ;;
  esac
}

tmp="$OUT.tmp.$$"
{
  echo "# Roadmap Next Actions"
  echo
  echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Repo HEAD: $(git rev-parse --short HEAD)"
  echo "Branch:    $(git rev-parse --abbrev-ref HEAD)"
  echo
  echo "This is an experimental deterministic project-management scan. It does not build anything; it only infers the likely next planning action from files under \`docs/roadmap/<feature-slug>/\`."
  echo
  echo "Each roadmap item has front matter in its feature \`README.md\`: \`id\`, \`title\`, \`status\`, \`priority\`, \`blocked_by\`, \`stage\`, \`owner\`, and \`updated\`."
  echo
  echo "Planning actions after \`clarify-feature\` are intended for the \`pm-assistant\` role, except \`review-prototypes\` and \`review-architecture\`, which require user judgment. \`clarify-feature\`, \`blocked\`, \`review-prototypes\`, and \`review-architecture\` require user input."
  echo
  echo "## Selector"
  echo
  echo "For each feature, blocked metadata or open questions win first; otherwise the first missing artifact wins:"
  echo
  echo "1. \`status: blocked\`, non-empty \`blocked_by\`, or \`open-questions.md\` -> blocked"
  echo "2. \`notes.md\` -> clarify-feature"
  echo "3. \`user-stories.md\` -> draft-user-stories"
  echo "4. \`existing-state.md\` -> inspect-existing-state"
  echo "5. \`prototypes/*\` -> build-prototypes"
  echo "6. \`ux-review.md\` -> review-prototypes"
  echo "7. \`architecture.md\` -> write-architecture"
  echo "8. \`architecture-review.md\` -> review-architecture"
  echo "9. \`spec.md\` -> write-spec"
  echo "10. \`plan.md\` -> write-plan"
  echo "11. \`implementation-handoff.md\` -> write-implementation-handoff"
  echo "12. all present -> ready-for-build-queue"
  echo
  echo "## Next User Item"
  echo

  user_written=0
  agent_written=0
  rows_file="$OUT.rows.$$"
  : > "$rows_file"

  while IFS= read -r dir; do
    title="$(read_title "$dir")"
    slug="$(basename "$dir")"
    id="$(feature_meta "$dir" "id" "?")"
    status="$(feature_meta "$dir" "status" "unknown")"
    priority="$(feature_meta "$dir" "priority" "unset")"
    blocked_by="$(feature_meta "$dir" "blocked_by" "[]")"
    IFS=$'\t' read -r action reason hint < <(classify_feature "$dir")
    agent="$(action_agent "$action")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$action" "$agent" "$id" "$title" "$slug" "$status" "$priority" "$blocked_by" "$reason" "$hint" >> "$rows_file"
  done < <(roadmap_dirs)

  while IFS=$'\t' read -r action agent id title slug status priority blocked_by reason hint; do
    if [ "$user_written" -eq 0 ] && [ "$agent" = "user" ]; then
      echo "- **Item:** $id"
      echo "- **Feature:** $title"
      echo "- **Priority:** \`$priority\`"
      echo "- **Status:** \`$status\`"
      echo "- **Action:** \`$action\`"
      echo "- **Role:** \`$agent\`"
      echo "- **Why:** $reason"
      echo "- **Output:** $hint"
      user_written=1
    fi
  done < "$rows_file"

  if [ "$user_written" -eq 0 ]; then
    echo "- No roadmap items currently require user input."
  fi

  echo
  echo "## Next Agent Item"
  echo

  while IFS=$'\t' read -r action agent id title slug status priority blocked_by reason hint; do
    if [ "$agent_written" -eq 0 ] && [ "$agent" = "pm-assistant" ]; then
      echo "- **Item:** $id"
      echo "- **Feature:** $title"
      echo "- **Priority:** \`$priority\`"
      echo "- **Status:** \`$status\`"
      echo "- **Action:** \`$action\`"
      echo "- **Role:** \`$agent\`"
      echo "- **Why:** $reason"
      echo "- **Output:** $hint"
      agent_written=1
    fi
  done < "$rows_file"

  if [ "$agent_written" -eq 0 ]; then
    echo "- No roadmap items currently have an autonomous PM-assistant action."
  fi

  echo
  echo "## Feature Actions"
  echo

  while IFS=$'\t' read -r action agent id title slug status priority blocked_by reason hint; do
    echo "### $id. $title"
    echo
    echo "- **Directory:** \`docs/roadmap/$slug/\`"
    echo "- **Status:** \`$status\`"
    echo "- **Priority:** \`$priority\`"
    echo "- **Blocked by:** \`$blocked_by\`"
    echo "- **Next action:** \`$action\`"
    echo "- **Role:** \`$agent\`"
    echo "- **Reason:** $reason"
    echo "- **Suggested output:** $hint"
    echo
  done < "$rows_file"

  rm -f "$rows_file"
} > "$tmp"

mv -f "$tmp" "$OUT"
echo "Wrote $OUT"
