#!/usr/bin/env bash
set -euo pipefail

project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$project_root"

actor_failures=".meta/multipass/state/actor-failures.ndjson"
inbox_root=".meta/multipass/runtime/inbox"

usage() {
  cat <<'EOF'
Usage: scripts/multi-pass/process-evidence-status.sh [options]

Read-only process evidence helper.

Options:
  --latest-usage-rate-limit       Report the latest compact usage_rate_limit failure.
  --failure PATH_OR_ID            Report one failure by result path, request path, or evidence id.
  --batch PATH                    Report gate status for one observe/batches/*/batch.yaml.
  --checkpoint LOOP COMMIT        Report gate status for the batch matching a loop/checkpoint commit.
  --help                          Show this help.

With no options, reports the latest usage_rate_limit failure. Use --checkpoint
or --batch for exact gate status.
EOF
}

strip_quotes() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^"//; s/"$//'
}

yaml_scalar() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    $1 == key ":" {
      sub("^[^:]*:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print
      exit
    }
  ' "$file"
}

frontmatter_value() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      split($0, parts, ":")
      if (parts[1] == key) {
        sub("^[^:]*:[[:space:]]*", "", $0)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print
        exit
      }
    }
  ' "$file"
}

loop_config_file() {
  local loop="$1"
  if [[ -f ".meta/multipass/config/loops/${loop}.yaml" ]]; then
    printf '%s\n' ".meta/multipass/config/loops/${loop}.yaml"
  elif [[ -f ".meta/multipass/runtime/loops/${loop}/manifest.yaml" ]]; then
    printf '%s\n' ".meta/multipass/runtime/loops/${loop}/manifest.yaml"
  fi
}

markdown_cell() {
  local value="$1"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

relative_or_raw() {
  local path="$1"
  if [[ "$path" == "$project_root/"* ]]; then
    printf '%s' "${path#"$project_root/"}"
  else
    printf '%s' "$path"
  fi
}

git_checkout_summary() {
  local loop="$1"
  local config worktree configured_branch actual_branch head dirty_count staged_count unstaged_count untracked_count

  config="$(loop_config_file "$loop")"
  worktree=""
  configured_branch=""
  if [[ -n "$config" ]]; then
    worktree="$(yaml_scalar worktree "$config")"
    configured_branch="$(yaml_scalar branch "$config")"
  fi
  if [[ -z "$worktree" && "$loop" == "project" ]]; then
    worktree="."
  fi

  if [[ -z "$worktree" || ! -d "$worktree" ]]; then
    echo "- loop config: ${config:-missing}"
    echo "- worktree: ${worktree:-unknown} (missing)"
    echo "- branch: ${configured_branch:-unknown}"
    echo "- HEAD: unknown"
    echo "- dirty state: unknown"
    return
  fi

  actual_branch="$(git -C "$worktree" branch --show-current 2>/dev/null || true)"
  head="$(git -C "$worktree" rev-parse HEAD 2>/dev/null || true)"
  dirty_count="$(git -C "$worktree" status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')"
  staged_count="$(git -C "$worktree" diff --cached --name-only 2>/dev/null | wc -l | tr -d '[:space:]')"
  unstaged_count="$(git -C "$worktree" diff --name-only 2>/dev/null | wc -l | tr -d '[:space:]')"
  untracked_count="$(git -C "$worktree" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d '[:space:]')"

  echo "- loop config: ${config:-missing}"
  echo "- worktree: $worktree"
  echo "- branch: ${actual_branch:-${configured_branch:-unknown}}"
  if [[ -n "$configured_branch" && -n "$actual_branch" && "$configured_branch" != "$actual_branch" ]]; then
    echo "- configured branch: $configured_branch"
  fi
  echo "- HEAD: ${head:-unknown}"
  echo "- dirty state: ${dirty_count:-unknown} path(s) total; staged ${staged_count:-unknown}, unstaged ${unstaged_count:-unknown}, untracked ${untracked_count:-unknown}"

  if [[ "${dirty_count:-0}" != "0" ]]; then
    echo "- dirty files:"
    git -C "$worktree" status --porcelain 2>/dev/null | sed -n '1,20p' | while IFS= read -r line; do
      echo "  - \`$line\`"
    done
  fi
}

extract_failure_field() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    $0 ~ "^- " key ":" {
      sub("^- " key ":[[:space:]]*", "", $0)
      gsub(/^`|`$/, "", $0)
      print
      exit
    }
  ' "$file"
}

checks_from_final() {
  local final="$1"
  if [[ ! -f "$final" ]]; then
    echo "- completed checks: no compact final artifact exists for this run"
    return
  fi

  local checks
  checks="$(awk '
    /^Checks run:/ { in_checks = 1; print; next }
    /^## Checks Run/ { in_checks = 1; print; next }
    in_checks && /^## / { exit }
    in_checks && NF { print }
  ' "$final" | sed -n '1,24p')"

  if [[ -n "$checks" ]]; then
    echo "$checks"
  else
    echo "- completed checks: compact final exists but no checks section was found"
  fi
}

failure_json_by_arg() {
  local arg="$1"
  [[ -f "$actor_failures" ]] || return 1
  jq -rc --arg arg "$arg" '
    select(.result == $arg or .request == $arg or .id == $arg or (.result | endswith($arg)) or (.request | endswith($arg)))
  ' "$actor_failures" | tail -n 1
}

latest_usage_failure_json() {
  [[ -f "$actor_failures" ]] || return 1
  jq -rc 'select(.mode == "usage_rate_limit")' "$actor_failures" | tail -n 1
}

report_failure_json() {
  local json="$1"
  if [[ -z "$json" ]]; then
    echo "No matching compact failure evidence found."
    return 1
  fi

  local id at loop phase actor mode signal request result summary
  id="$(jq -r '.id // "unknown"' <<<"$json")"
  at="$(jq -r '.at // "unknown"' <<<"$json")"
  loop="$(jq -r '.loop // "unknown"' <<<"$json")"
  phase="$(jq -r '.phase // "unknown"' <<<"$json")"
  actor="$(jq -r '.actor // "unknown"' <<<"$json")"
  mode="$(jq -r '.mode // "unknown"' <<<"$json")"
  signal="$(jq -r '.signal // "unknown"' <<<"$json")"
  request="$(jq -r '.request // "unknown"' <<<"$json")"
  result="$(jq -r '.result // "unknown"' <<<"$json")"
  summary="$(jq -r '.summary // "unknown"' <<<"$json")"

  echo "## Rate-Limit / Failure Evidence"
  echo
  echo "| field | value |"
  echo "| --- | --- |"
  printf '| id | `%s` |\n' "$(markdown_cell "$id")"
  printf '| at | `%s` |\n' "$(markdown_cell "$at")"
  printf '| loop | `%s` |\n' "$(markdown_cell "$loop")"
  printf '| phase | `%s` |\n' "$(markdown_cell "$phase")"
  printf '| actor | `%s` |\n' "$(markdown_cell "$actor")"
  printf '| mode | `%s` |\n' "$(markdown_cell "$mode")"
  printf '| signal | `%s` |\n' "$(markdown_cell "$signal")"
  printf '| request | `%s` |\n' "$(markdown_cell "$request")"
  printf '| result | `%s` |\n' "$(markdown_cell "$result")"
  printf '| summary | %s |\n' "$(markdown_cell "$summary")"
  echo

  if [[ -f "$request" ]]; then
    echo "### Request Frontmatter"
    echo
    echo "- title: $(frontmatter_value title "$request")"
    echo "- priority: $(frontmatter_value priority "$request")"
    echo "- status: $(frontmatter_value status "$request")"
    echo "- to: $(frontmatter_value to "$request")"
    echo "- loop: $(frontmatter_value loop "$request")"
    echo "- phase: $(frontmatter_value phase "$request")"
    echo
  else
    echo "### Request Frontmatter"
    echo
    echo "- request file missing or not readable: \`$request\`"
    echo
  fi

  echo "### Checkout State"
  echo
  git_checkout_summary "$loop"
  echo

  echo "### Completed Checks"
  echo
  local final_target=""
  if [[ -f "$result" ]]; then
    final_target="$(extract_failure_field missing_final_target "$result")"
  fi
  if [[ -n "$final_target" ]]; then
    checks_from_final "$final_target"
  else
    checks_from_final "${result%.failure.md}.final.md"
  fi
  echo
}

expected_gates() {
  local batch="$1"
  awk '
    $1 == "expected:" { in_expected = 1; next }
    in_expected && $1 == "-" {
      sub("^[[:space:]]*-[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print
      next
    }
    in_expected && $0 !~ /^[[:space:]]/ { exit }
  ' "$batch"
}

latest_actor_artifact() {
  local loop="$1"
  local actor="$2"
  find \
    ".meta/multipass/runtime/loops/${loop}/observe/${actor}" \
    ".meta/multipass/runtime/runs/actors/${actor}" \
    -type f \( -name '*.md' -o -name '*.final.md' \) 2>/dev/null \
    | while IFS= read -r file; do
        printf '%s\t%s\n' "$(stat -f '%m' "$file" 2>/dev/null || stat -c '%Y' "$file")" "$file"
      done \
    | sort -rn \
    | awk -F '\t' 'NR == 1 { print $2 }'
}

matching_actor_artifact() {
  local loop="$1"
  local actor="$2"
  local exact="$3"
  local batch_id="$4"
  local roots=()

  [[ -d ".meta/multipass/runtime/loops/${loop}/observe/${actor}" ]] && roots+=(".meta/multipass/runtime/loops/${loop}/observe/${actor}")
  [[ -d ".meta/multipass/runtime/runs/actors/${actor}" ]] && roots+=(".meta/multipass/runtime/runs/actors/${actor}")
  [[ "${#roots[@]}" -gt 0 ]] || return 0

  {
    [[ -n "$exact" ]] && rg -l -F "$exact" "${roots[@]}" -g '*.md' 2>/dev/null || true
    [[ -n "$batch_id" ]] && rg -l -F "$batch_id" "${roots[@]}" -g '*.md' 2>/dev/null || true
  } \
    | sort -u \
    | while IFS= read -r file; do
        local priority=0
        if rg -q '^- (result|verdict|decision):' "$file"; then
          priority=2
        elif rg -q '^Request handled:' "$file"; then
          priority=1
        fi
        printf '%s\t%s\t%s\n' "$priority" "$(stat -f '%m' "$file" 2>/dev/null || stat -c '%Y' "$file")" "$file"
      done \
    | sort -t "$(printf '\t')" -k1,1nr -k2,2nr \
    | awk -F '\t' 'NR == 1 { print $3 }'
}

blocked_gate_request() {
  local actor="$1"
  local exact="$2"
  local batch_id="$3"
  [[ -d "$inbox_root/blocked" ]] || return 0
  find "$inbox_root/blocked" -maxdepth 1 -type f -name '*.md' 2>/dev/null \
    | while IFS= read -r file; do
        if rg -q -F "$actor" "$file" && { { [[ -n "$exact" ]] && rg -q -F "$exact" "$file"; } || { [[ -n "$batch_id" ]] && rg -q -F "$batch_id" "$file"; }; }; then
          echo "$file"
        fi
      done \
    | sort \
    | tail -n 1
}

extract_result_line() {
  local file="$1"
  awk '
    /^- (result|verdict|decision):/ {
      sub("^- (result|verdict|decision):[[:space:]]*", "", $0)
      print
      exit
    }
    /^Request handled:/ {
      print "handled"
      exit
    }
    / passed[.]?$/ || /: pass/ || /testing-pass/ || /visual-economy-pass/ || /ux-ia-pass/ {
      print "pass-like"
      exit
    }
  ' "$file" | head -n 1
}

find_batch_for_checkpoint() {
  local loop="$1"
  local commit="$2"
  find ".meta/multipass/runtime/loops/${loop}/observe/batches" -type f -name batch.yaml 2>/dev/null \
    | while IFS= read -r batch; do
        exact="$(yaml_scalar exact_commit "$batch")"
        if [[ "$exact" == "$commit"* || "$commit" == "$exact"* ]]; then
          printf '%s\t%s\n' "$(stat -f '%m' "$batch" 2>/dev/null || stat -c '%Y' "$batch")" "$batch"
        fi
      done \
    | sort -rn \
    | awk -F '\t' 'NR == 1 { print $2 }'
}

report_batch() {
  local batch="$1"
  if [[ ! -f "$batch" ]]; then
    echo "Batch file not found: \`$batch\`"
    return 1
  fi

  local batch_id loop subject exact status expected_count present_count blocked_count missing_count stale_count
  batch_id="$(yaml_scalar id "$batch")"
  loop="$(yaml_scalar loop "$batch")"
  subject="$(yaml_scalar subject "$batch")"
  exact="$(yaml_scalar exact_commit "$batch")"
  status="$(yaml_scalar status "$batch")"
  expected_count=0
  present_count=0
  blocked_count=0
  missing_count=0
  stale_count=0

  echo "## Batch Gate Status"
  echo
  echo "- batch: \`$batch\`"
  echo "- id: \`${batch_id:-unknown}\`"
  echo "- loop: \`${loop:-unknown}\`"
  echo "- subject: ${subject:-unknown}"
  echo "- exact_commit: \`${exact:-unknown}\`"
  echo "- metadata_status: \`${status:-unknown}\`"
  echo
  echo "| gate actor | status | result | evidence |"
  echo "| --- | --- | --- | --- |"

  while IFS= read -r gate; do
    [[ -n "$gate" ]] || continue
    expected_count=$((expected_count + 1))

    local evidence latest blocked result gate_status evidence_cell
    evidence="$(matching_actor_artifact "$loop" "$gate" "$exact" "$batch_id")"
    latest=""
    blocked=""
    result=""
    gate_status=""
    evidence_cell=""

    if [[ -n "$evidence" ]]; then
      gate_status="present"
      present_count=$((present_count + 1))
      result="$(extract_result_line "$evidence")"
      evidence_cell="\`$evidence\`"
    else
      blocked="$(blocked_gate_request "$gate" "$exact" "$batch_id")"
      if [[ -n "$blocked" ]]; then
        gate_status="blocked"
        blocked_count=$((blocked_count + 1))
        evidence_cell="\`$blocked\`"
      else
        latest="$(latest_actor_artifact "$loop" "$gate")"
        if [[ -n "$latest" ]]; then
          gate_status="stale"
          stale_count=$((stale_count + 1))
          evidence_cell="latest \`$latest\` does not name this checkpoint"
        else
          gate_status="missing"
          missing_count=$((missing_count + 1))
          evidence_cell="none found"
        fi
      fi
    fi

    printf '| %s | %s | %s | %s |\n' \
      "$(markdown_cell "$gate")" \
      "$(markdown_cell "$gate_status")" \
      "$(markdown_cell "${result:-n/a}")" \
      "$evidence_cell"
  done < <(expected_gates "$batch")

  echo
  echo "### Batch Summary"
  echo
  echo "- expected gates: $expected_count"
  echo "- present: $present_count"
  echo "- blocked: $blocked_count"
  echo "- stale: $stale_count"
  echo "- missing: $missing_count"
  if [[ "${status:-unknown}" == "open" && "$expected_count" -gt 0 && "$present_count" -eq "$expected_count" ]]; then
    echo "- closure read: metadata stale/open; all expected gates are present"
  elif [[ "${status:-unknown}" != "open" && "$((blocked_count + missing_count + stale_count))" -gt 0 ]]; then
    echo "- closure read: metadata stale/closed; not all expected gates are present"
  elif [[ "$blocked_count" -gt 0 || "$missing_count" -gt 0 || "$stale_count" -gt 0 ]]; then
    echo "- closure read: incomplete"
  else
    echo "- closure read: complete"
  fi
  echo
}

failure_arg=""
batch_arg=""
checkpoint_loop=""
checkpoint_commit=""
show_latest_failure=0
explicit=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --latest-usage-rate-limit)
      show_latest_failure=1
      explicit=1
      shift
      ;;
    --failure)
      failure_arg="${2:-}"
      explicit=1
      shift 2
      ;;
    --batch)
      batch_arg="${2:-}"
      explicit=1
      shift 2
      ;;
    --checkpoint)
      checkpoint_loop="${2:-}"
      checkpoint_commit="${3:-}"
      explicit=1
      shift 3
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

echo "# Process Evidence Status"
echo
echo "- command_id: process-evidence-status"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $project_root"
echo

if [[ "$explicit" -eq 0 || "$show_latest_failure" -eq 1 ]]; then
  report_failure_json "$(latest_usage_failure_json || true)"
fi

if [[ -n "$failure_arg" ]]; then
  report_failure_json "$(failure_json_by_arg "$failure_arg" || true)"
fi

if [[ -n "$checkpoint_loop" || -n "$checkpoint_commit" ]]; then
  if [[ -z "$checkpoint_loop" || -z "$checkpoint_commit" ]]; then
    echo "--checkpoint requires LOOP and COMMIT" >&2
    exit 2
  fi
  batch_arg="$(find_batch_for_checkpoint "$checkpoint_loop" "$checkpoint_commit")"
  if [[ -z "$batch_arg" ]]; then
    echo "No batch found for loop \`$checkpoint_loop\` checkpoint \`$checkpoint_commit\`."
    exit 1
  fi
fi

if [[ -n "$batch_arg" ]]; then
  report_batch "$batch_arg"
elif [[ "$explicit" -eq 0 ]]; then
  echo "## Batch Gate Status"
  echo
  echo "- no batch requested; use \`--checkpoint LOOP COMMIT\` or \`--batch PATH\` for exact gate status"
fi
