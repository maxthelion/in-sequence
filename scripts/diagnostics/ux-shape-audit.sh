#!/usr/bin/env bash
set -euo pipefail

# ux-shape-audit — reports rounded-corner and stroke-width usage across the
# SwiftUI surface. Default mode is informational so the current historical
# exceptions can be triaged before this becomes a hard UX canon gate.
#
# Usage:
#   scripts/diagnostics/ux-shape-audit.sh
#   scripts/diagnostics/ux-shape-audit.sh --strict
#   scripts/diagnostics/ux-shape-audit.sh Sources/UI/Track/TrackWorkspaceView.swift

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
strict=0
files=()

while (($# > 0)); do
  case "$1" in
    --strict)
      strict=1
      ;;
    *)
      files+=("$1")
      ;;
  esac
  shift
done

if ((${#files[@]} == 0)); then
  while IFS= read -r file; do
    files+=("$file")
  done < <(find "$repo_root/Sources/UI" "$repo_root/Sources/StepGrid" -name '*.swift' | LC_ALL=C sort)
fi

for i in "${!files[@]}"; do
  if [[ "${files[$i]}" != /* ]]; then
    files[$i]="$repo_root/${files[$i]}"
  fi
  [[ -f "${files[$i]}" ]] || { printf 'ux-shape-audit: no such file: %s\n' "${files[$i]}" >&2; exit 127; }
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

token_hits="$tmpdir/token-hits.txt"
radius_literals="$tmpdir/radius-literals.txt"
stroke_literals="$tmpdir/stroke-literals.txt"
shape_width_helpers="$tmpdir/shape-width-helpers.txt"

rg -No 'StudioMetrics\.CornerRadius\.[A-Za-z0-9_]+' "${files[@]}" \
  | sed -E 's/.*(StudioMetrics\.CornerRadius\.[A-Za-z0-9_]+)/\1/' \
  | LC_ALL=C sort \
  | uniq -c \
  | sed -E 's/^[[:space:]]*([0-9]+)[[:space:]]+/\1 /' \
  > "$token_hits" || true

rg -n \
  'RoundedRectangle\(cornerRadius:[[:space:]]*[0-9]|UnevenRoundedRectangle\(.*cornerRadius:[[:space:]]*[0-9]|\.cornerRadius\([[:space:]]*[0-9]|cornerRadius:[[:space:]]*CGFloat[[:space:]]*=[[:space:]]*[0-9]|iconCornerRadius:[[:space:]]*[0-9]' \
  "${files[@]}" \
  > "$radius_literals" || true

rg -n \
  'lineWidth:[^,)]*[0-9]+(\.[0-9]+)?|StrokeStyle\(lineWidth:[^,)]*[0-9]+(\.[0-9]+)?' \
  "${files[@]}" \
  > "$stroke_literals" || true

for path in "${files[@]}"; do
  display="${path#"$repo_root"/}"
  [[ "$display" == "Sources/UI/Theme/StudioMetrics.swift" ]] && continue
  awk -v file="$display" '
    /^[[:space:]]*(private[[:space:]]+|static[[:space:]]+)?(func|var|let)[[:space:]].*(borderWidth|strokeWidth|lineWidth).*CGFloat/ {
      in_helper = 1
    }
    in_helper && ($0 ~ /return[[:space:]]+.*[0-9]+(\.[0-9]+)?/ || $0 ~ /^[[:space:]]*\?[[:space:]]*[0-9]+(\.[0-9]+)?/ || $0 ~ /\?[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*:/ || $0 ~ /=[[:space:]]*[0-9]+(\.[0-9]+)?/) {
      printf "%s:%d:%s\n", file, NR, $0
    }
    in_helper && /^[[:space:]]*}/ {
      in_helper = 0
    }
  ' "$path" >> "$shape_width_helpers"
done

scanned_count="${#files[@]}"
token_count="$(awk '{ sum += $1 } END { print sum + 0 }' "$token_hits")"
radius_literal_count="$(wc -l < "$radius_literals" | tr -d ' ')"
stroke_literal_count="$(wc -l < "$stroke_literals" | tr -d ' ')"
shape_width_helper_count="$(wc -l < "$shape_width_helpers" | tr -d ' ')"
border_token_count="$(rg -No 'StudioMetrics\.borderWidth' "${files[@]}" | wc -l | tr -d ' ' || true)"

printf 'UX shape audit\n'
printf 'Files scanned: %s\n' "$scanned_count"
printf 'Corner radius token uses: %s\n' "$token_count"
printf 'Border width token uses: %s\n' "$border_token_count"
printf 'Raw corner radius literals: %s\n' "$radius_literal_count"
printf 'Raw stroke width literals: %s\n' "$stroke_literal_count"
printf 'Raw shape width helper literals: %s\n' "$shape_width_helper_count"

printf '\nCorner radius token usage:\n'
if [[ -s "$token_hits" ]]; then
  cat "$token_hits"
else
  printf 'none\n'
fi

printf '\nRaw corner radius literals:\n'
if [[ -s "$radius_literals" ]]; then
  sed "s#^$repo_root/##" "$radius_literals"
else
  printf 'none\n'
fi

printf '\nRaw stroke width literals:\n'
if [[ -s "$stroke_literals" ]]; then
  sed "s#^$repo_root/##" "$stroke_literals"
else
  printf 'none\n'
fi

printf '\nRaw shape width helper literals:\n'
if [[ -s "$shape_width_helpers" ]]; then
  cat "$shape_width_helpers"
else
  printf 'none\n'
fi

if ((strict == 1)) && ((radius_literal_count + stroke_literal_count + shape_width_helper_count > 0)); then
  printf '\nux-shape-audit --strict failed: replace raw shape literals with StudioMetrics tokens or annotate/tokenize intentional drawing exceptions.\n' >&2
  exit 1
fi
