#!/usr/bin/env bash
set -euo pipefail

min_free_gib="${MULTIPASS_XCODE_FREE_MIN_GIB:-8}"
warn_free_gib="${MULTIPASS_XCODE_FREE_WARN_GIB:-12}"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

bytes_for_path() {
  local path="$1"
  df -Pk "$path" 2>/dev/null | awk 'NR == 2 { print $4 * 1024 }'
}

gib_from_bytes() {
  awk -v bytes="${1:-0}" 'BEGIN { printf "%.2f", bytes / 1024 / 1024 / 1024 }'
}

verdict_for_bytes() {
  local bytes="${1:-0}"
  local min_bytes
  local warn_bytes
  min_bytes="$(awk -v gib="$min_free_gib" 'BEGIN { printf "%.0f", gib * 1024 * 1024 * 1024 }')"
  warn_bytes="$(awk -v gib="$warn_free_gib" 'BEGIN { printf "%.0f", gib * 1024 * 1024 * 1024 }')"

  if awk -v b="$bytes" -v m="$min_bytes" 'BEGIN { exit !(b < m) }'; then
    echo "blocked_for_broad_xcode_evidence"
  elif awk -v b="$bytes" -v w="$warn_bytes" 'BEGIN { exit !(b < w) }'; then
    echo "tight_for_broad_xcode_evidence"
  else
    echo "ok_for_bounded_evidence"
  fi
}

print_volume_row() {
  local label="$1"
  local path="$2"
  local bytes
  if [ ! -e "$path" ]; then
    echo "| $label | $path | missing | missing |"
    return
  fi

  bytes="$(bytes_for_path "$path")"
  echo "| $label | $path | $(gib_from_bytes "$bytes") GiB | $(verdict_for_bytes "$bytes") |"
}

echo "# Evidence: Disk Preflight"
echo
echo "- command_id: evidence-disk-preflight"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $repo_root"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo "- dirty_count: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
echo "- min_free_gib: $min_free_gib"
echo "- warn_free_gib: $warn_free_gib"
echo

echo "## Volume Free Space"
echo
echo "| Label | Path | Available | Verdict |"
echo "| --- | --- | ---: | --- |"
print_volume_row "data" "/System/Volumes/Data"
print_volume_row "tmp" "/tmp"
print_volume_row "repo" "$repo_root"
print_volume_row "derived-data" "$HOME/Library/Developer/Xcode/DerivedData"
echo

data_bytes="$(bytes_for_path /System/Volumes/Data || echo 0)"
tmp_bytes="$(bytes_for_path /tmp || echo 0)"
data_verdict="$(verdict_for_bytes "$data_bytes")"
tmp_verdict="$(verdict_for_bytes "$tmp_bytes")"

echo "## Evidence Guidance"
echo
if [ "$data_verdict" = "blocked_for_broad_xcode_evidence" ] || [ "$tmp_verdict" = "blocked_for_broad_xcode_evidence" ]; then
  echo "- status: blocked_for_broad_xcode_evidence"
  echo "- guidance: Do not spend actor time on broad Xcode build/test reruns, result-bundle-heavy commands, or repeated visual capture until disk is freed or evidence paths are moved to a larger volume."
  echo "- acceptable_fallback: Record this preflight, run cheap checks such as \`git diff --check\`, and run only tightly scoped tests when their result-bundle footprint is known to fit."
elif [ "$data_verdict" = "tight_for_broad_xcode_evidence" ] || [ "$tmp_verdict" = "tight_for_broad_xcode_evidence" ]; then
  echo "- status: tight_for_broad_xcode_evidence"
  echo "- guidance: Prefer focused Xcode commands and explicit result-bundle paths; avoid broad reruns unless the request requires them."
else
  echo "- status: ok_for_bounded_evidence"
  echo "- guidance: Disk space is not currently the first blocker for bounded Xcode or visual evidence."
fi
echo

echo "## Recent Result Bundles"
echo
result_paths=()
while IFS= read -r -d '' result; do
  result_paths+=("$result")
done < <(
  find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 8 -path '*/Logs/Test/*.xcresult' -type d -print0 2>/dev/null
  find /tmp -maxdepth 1 -name '*.xcresult' -type d -print0 2>/dev/null
)

if [ "${#result_paths[@]}" -eq 0 ]; then
  echo "- none found"
else
  while IFS= read -r result; do
    size="$(du -sh "$result" 2>/dev/null | awk '{ print $1 }')"
    echo "- $size $result"
  done < <(ls -td "${result_paths[@]}" 2>/dev/null | sed -n '1,12p')
fi
