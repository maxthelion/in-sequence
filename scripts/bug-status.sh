#!/usr/bin/env bash
# bug-status.sh — count + list bug reports under docs/bugs/ by status.
#
# STATUS CONVENTION (per bug dir, read from any *.md inside it):
#   RESOLVED — the dir has a `Status: RESOLVED|FIXED|DONE` line, OR a
#              `## RESOLVED` / `## ROOT CAUSE + FIX` heading, OR `RESOLVED (20..`.
#   WONTFIX  — a `Status: WONTFIX|WON'T FIX|DUPLICATE|INVALID` line.
#   OPEN     — anything else (the default; freshly-filed intake bugs are OPEN).
# When you fix (or reject) a bug, add a `Status: RESOLVED` (or `Status: WONTFIX`)
# line to its note.md/report.md so this report stays accurate.
#
# Usage:
#   scripts/bug-status.sh            # summary counts
#   scripts/bug-status.sh --open     # + list the OPEN bug dirs
#   scripts/bug-status.sh --all      # + list every bug dir with its status

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUGS="$REPO/docs/bugs"

mode="${1:-}"
resolved=0; wontfix=0; open=0; total=0
open_list=(); all_list=()

for dir in "$BUGS"/*/; do
  [ -d "$dir" ] || continue
  total=$((total + 1))
  name="$(basename "$dir")"
  md="$(cat "$dir"*.md 2>/dev/null || true)"

  if printf '%s\n' "$md" | grep -qiE '^[[:space:]]*status:[[:space:]]*(resolved|fixed|done)|^#+[[:space:]]*resolved\b|^#+[[:space:]]*root cause \+ fix|resolved \(20'; then
    status="RESOLVED"; resolved=$((resolved + 1))
  elif printf '%s\n' "$md" | grep -qiE "^[[:space:]]*status:[[:space:]]*(wontfix|won't fix|duplicate|invalid)"; then
    status="WONTFIX"; wontfix=$((wontfix + 1))
  else
    status="OPEN"; open=$((open + 1)); open_list+=("$name")
  fi
  all_list+=("$status  $name")
done

echo "Bug reports under docs/bugs/  (total: $total)"
echo "  RESOLVED: $resolved"
echo "  WONTFIX:  $wontfix"
echo "  OPEN:     $open"

if [ "$mode" = "--open" ] || [ "$mode" = "-o" ]; then
  echo ""
  echo "OPEN ($open):"
  printf '  - %s\n' "${open_list[@]}"
elif [ "$mode" = "--all" ] || [ "$mode" = "-a" ]; then
  echo ""
  printf '%s\n' "${all_list[@]}" | sort
fi
