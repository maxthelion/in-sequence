#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
d2_bin="${D2_BIN:-d2}"

if ! command -v "$d2_bin" >/dev/null 2>&1; then
  cat >&2 <<'EOF'
render-d2.sh requires the D2 CLI.

Install D2 locally, for example:
  brew install d2

Or set D2_BIN=/path/to/d2.
EOF
  exit 127
fi

src_dir="$repo_root/docs/diagrams/src"
out_dir="$repo_root/docs/diagrams"

for source in "$src_dir"/*.d2; do
  name="$(basename "$source" .d2)"
  [[ "$name" == "styles" ]] && continue
  log="$(mktemp "${TMPDIR:-/tmp}/d2-render.XXXXXX")"
  if ! "$d2_bin" --layout=elk "$source" "$out_dir/$name.svg" >"$log" 2>&1; then
    cat "$log" >&2
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
done
