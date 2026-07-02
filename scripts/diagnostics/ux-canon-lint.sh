#!/usr/bin/env bash
set -euo pipefail

# ux-canon-lint — deterministic guard for the UX canon (docs/ux-canon.md) on
# the UI surfaces, wired next to the audio lints so canon creep pass #4 never
# ships. Companion to the unified tab grammar (docs/roadmap/track-view-ia/
# tab-unification-and-canon-creep.md → DECISION).
#
# Usage:
#   scripts/diagnostics/ux-canon-lint.sh              # scan Sources/UI
#   scripts/diagnostics/ux-canon-lint.sh <files...>   # scan specific files
#
# Rules enforced here:
#   1. translucent-accent-fill — `accent.opacity(`/`stateColor.opacity(` used
#      as a `.fill(`/`.background(` in Sources/UI outside Theme/ (canon Rule
#      12: colour identifies, it never floods — accents are solid thumbs or
#      outlines, never translucent washes). Fully-opaque
#      `.opacity(StudioOpacity.accentFill)` is exempt.
#   2. grey-escape — `.foregroundColor(.secondary)` / `.foregroundStyle(
#      .secondary)` / `Color.gray` / `.tertiary` in Sources/UI outside Theme/:
#      system greys bypass the StudioTheme tokens and re-grow the wall of
#      grey (the bold-flat pass).
#   3. explainer-prose — a `Text("...")` literal that ends with a period and
#      exceeds 4 words (canon Rule 3: no explainer prose on working
#      surfaces; any full sentence is a finding). Legitimate sentence slots
#      (destructive-confirm messages) live in
#      scripts/diagnostics/ux-canon-prose-allowlist.txt.
#
# Every rule is opt-out via a `ux-canon-allow: <reason>` comment on the
# offending line or the line above it. A bare annotation with no reason is
# itself a failure.
#
# STRICT ZERO-TOLERANCE: the migration that this lint ratcheted (grey-default
# flip + label purge, 2026-07-02) landed, so ANY violation fails. There is no
# baseline/threshold escape hatch — legitimate sentence slots go in the
# allowlist file, legitimate neutral/opacity uses get an inline
# `ux-canon-allow: <reason>` annotation.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
allowlist="$repo_root/scripts/diagnostics/ux-canon-prose-allowlist.txt"

if (($# > 0)); then
  files=("$@")
else
  files=()
  while IFS= read -r file; do
    files+=("$file")
  done < <(find "$repo_root/Sources/UI" -name '*.swift' | LC_ALL=C sort)
fi

violations="$(mktemp)"
trap 'rm -f "$violations"' EXIT

for path in "${files[@]}"; do
  [[ -f "$path" ]] || { printf 'ux-canon-lint: no such file: %s\n' "$path" >&2; exit 127; }
  display="${path#"$repo_root"/}"

  in_theme=0
  case "$display" in
    Sources/UI/Theme/*) in_theme=1 ;;
  esac

  # Rules 1 + 2 apply outside Theme/ (the theme layer is where tokens are
  # defined and may compose opacities); rule 3 + annotation hygiene apply
  # everywhere under Sources/UI.
  awk -v file="$display" -v in_theme="$in_theme" -v allowfile="$allowlist" '
    function has_allow(line) {
      return line ~ /ux-canon-allow: .+/
    }
    function allowlisted(f, literal,    i) {
      for (i = 1; i <= allow_count; i++) {
        if (index(f, allow_path[i]) > 0 && index(literal, allow_snippet[i]) > 0) {
          return 1
        }
      }
      return 0
    }
    BEGIN {
      allow_count = 0
      while ((getline entry < allowfile) > 0) {
        if (entry ~ /^[[:space:]]*(#|$)/) continue
        sep = index(entry, "|")
        if (sep == 0) continue
        allow_count++
        allow_path[allow_count] = substr(entry, 1, sep - 1)
        allow_snippet[allow_count] = substr(entry, sep + 1)
      }
      close(allowfile)
    }
    {
      line = $0

      # Annotation hygiene: a bare ux-canon-allow with no reason fails.
      if (line ~ /ux-canon-allow/ && !has_allow(line)) {
        printf "bad-annotation|%s:%d: ux-canon-allow annotation must include a reason: %s\n", file, NR, line
        previous = line
        next
      }

      if (line ~ /^[[:space:]]*\/\//) { previous = line; next }

      if (!in_theme) {
        # Rule 1: translucent accent fill/background.
        stripped = line
        gsub(/\.opacity\(StudioOpacity\.accentFill\)/, "", stripped)
        if (stripped ~ /(accent|Accent|stateColor)\.opacity\(/ \
            && (line ~ /\.fill\(|\.background\(/ || previous ~ /(\.fill\(|\.background\()[[:space:]]*$/)) {
          if (!has_allow(line) && !has_allow(previous)) {
            printf "translucent-accent-fill|%s:%d: canon Rule 12 (colour identifies, never floods) violated: translucent accent fill — use a solid accent thumb, an outline stroke token, or annotate `// ux-canon-allow: <reason>`: %s\n", file, NR, line
          }
        }

        # Rule 2: system-grey escapes bypassing StudioTheme tokens.
        if (line ~ /\.foregroundColor\(\.secondary\)|\.foregroundStyle\(\.secondary\)|Color\.gray|\.tertiary/) {
          if (!has_allow(line) && !has_allow(previous)) {
            printf "grey-escape|%s:%d: canon (bold-flat) violated: system grey bypasses StudioTheme tokens — use StudioTheme.mutedText/border or annotate `// ux-canon-allow: <reason>`: %s\n", file, NR, line
          }
        }
      }

      # Rule 3: explainer-prose Text literal (ends with a period, > 4 words).
      idx = index(line, "Text(\"")
      if (idx > 0) {
        rest = substr(line, idx + 6)
        end = index(rest, "\")")
        if (end > 1) {
          literal = substr(rest, 1, end - 1)
          if (literal ~ /\.$/) {
            n = split(literal, words, /[[:space:]]+/)
            if (n > 4 && !allowlisted(file, literal) && !has_allow(line) && !has_allow(previous)) {
              printf "explainer-prose|%s:%d: canon Rule 3 (no explainer prose on surfaces) violated: sentence Text literal — delete it, move real state into a solid badge, or move instruction to a .help tooltip (destructive-confirm slots go in ux-canon-prose-allowlist.txt): %s\n", file, NR, line
            }
          }
        }
      }

      previous = line
    }
  ' "$path" >> "$violations"
done

count_rule() {
  grep -c "^$1|" "$violations" || true
}

fill_count="$(count_rule translucent-accent-fill)"
grey_count="$(count_rule grey-escape)"
prose_count="$(count_rule explainer-prose)"
annotation_count="$(count_rule bad-annotation)"
total=$((fill_count + grey_count + prose_count + annotation_count))

sed 's/^[a-z-]*|//' "$violations" >&2

printf 'ux-canon-lint: translucent-accent-fill=%d grey-escape=%d explainer-prose=%d bad-annotation=%d total=%d\n' \
  "$fill_count" "$grey_count" "$prose_count" "$annotation_count" "$total"

if ((total > 0)); then
  printf 'ux-canon-lint: FAIL (%d violations; zero tolerance)\n' "$total"
  exit 1
fi

printf 'ux-canon-lint: OK (0 violations)\n'
exit 0
