#!/usr/bin/env bash
set -euo pipefail

inbox_root=".meta/multipass/runtime/inbox"

count_requests() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    printf '0'
    return
  fi
  find "$dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d '[:space:]'
}

frontmatter_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      split($0, parts, ":")
      if (parts[1] == key) {
        sub("^[^:]*:[[:space:]]*", "", $0)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    }
  ' "$file"
}

field_or_unknown() {
  local key="$1"
  local file="$2"
  local value
  value="$(frontmatter_value "$key" "$file")"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf 'unknown'
  fi
}

loop_status() {
  local loop="$1"
  local loop_file=".meta/multipass/config/loops/${loop}.yaml"
  local manifest_file=".meta/multipass/runtime/loops/${loop}/manifest.yaml"
  local file=""

  if [[ -f "$loop_file" ]]; then
    file="$loop_file"
  elif [[ -f "$manifest_file" ]]; then
    file="$manifest_file"
  fi

  if [[ -z "$file" ]]; then
    printf 'unknown'
    return
  fi

  awk '$1 == "status:" { print $2; exit }' "$file"
}

markdown_cell() {
  local value="$1"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

echo "# Multi-Pass Inbox Status"
echo
echo "Runtime inbox: \`$inbox_root\`"
echo
echo "| status | count |"
echo "| --- | ---: |"
for status in pending claimed blocked done; do
  echo "| $status | $(count_requests "$inbox_root/$status") |"
done
echo

echo "## Pending Requests (Active/Unknown Loops)"
echo
if [[ ! -d "$inbox_root/pending" ]] || ! find "$inbox_root/pending" -maxdepth 1 -type f -name '*.md' -print -quit | grep -q .; then
  echo "No pending requests."
else
  pending_found=0
  echo "| path | to | loop | phase | priority | title | loop status |"
  echo "| --- | --- | --- | --- | --- | --- | --- |"
  while IFS= read -r file; do
    to="$(field_or_unknown to "$file")"
    loop="$(field_or_unknown loop "$file")"
    phase="$(field_or_unknown phase "$file")"
    priority="$(field_or_unknown priority "$file")"
    title="$(field_or_unknown title "$file")"
    status="$(loop_status "$loop")"
    if [[ "$status" != "active" && "$status" != "unknown" ]]; then
      continue
    fi
    pending_found=1
    printf '| `%s` | %s | %s | %s | %s | %s | %s |\n' \
      "$file" \
      "$(markdown_cell "$to")" \
      "$(markdown_cell "$loop")" \
      "$(markdown_cell "$phase")" \
      "$(markdown_cell "$priority")" \
      "$(markdown_cell "$title")" \
      "$(markdown_cell "$status")"
  done < <(find "$inbox_root/pending" -maxdepth 1 -type f -name '*.md' | sort)
  if [[ "$pending_found" -eq 0 ]]; then
    echo "| none |  |  |  |  |  |  |"
  fi
fi
echo

echo "## Pending Terminal-Loop Residue"
echo
residue_found=0
if [[ -d "$inbox_root/pending" ]]; then
  while IFS= read -r file; do
    loop="$(field_or_unknown loop "$file")"
    status="$(loop_status "$loop")"
    if [[ "$loop" == build/* && "$status" != "active" && "$status" != "unknown" ]]; then
      if [[ "$residue_found" -eq 0 ]]; then
        echo "| path | loop | loop status | title |"
        echo "| --- | --- | --- | --- |"
      fi
      residue_found=1
      title="$(field_or_unknown title "$file")"
      printf '| `%s` | %s | %s | %s |\n' \
        "$file" \
        "$(markdown_cell "$loop")" \
        "$(markdown_cell "$status")" \
        "$(markdown_cell "$title")"
    fi
  done < <(find "$inbox_root/pending" -maxdepth 1 -type f -name '*.md' | sort)
fi

if [[ "$residue_found" -eq 0 ]]; then
  echo "No pending requests target a terminal build loop."
fi
