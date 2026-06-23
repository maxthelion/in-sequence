#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
d2_bin="${D2_BIN:-d2}"

if ! command -v "$d2_bin" >/dev/null 2>&1; then
  message="check-d2-rendered.sh skipped: D2 CLI not found. Install with 'brew install d2' or set D2_BIN."
  if [[ "${REQUIRE_D2:-0}" == "1" ]]; then
    printf '%s\n' "$message" >&2
    exit 127
  fi
  printf '%s\n' "$message"
  exit 0
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sequencer-ai-d2.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

src_dir="$repo_root/docs/diagrams/src"
out_dir="$repo_root/docs/diagrams"

for source in "$src_dir"/*.d2; do
  name="$(basename "$source" .d2)"
  [[ "$name" == "styles" ]] && continue
  log="$tmp_dir/$name.render.log"
  if ! "$d2_bin" --layout=elk "$source" "$tmp_dir/$name.svg" >"$log" 2>&1; then
    cat "$log" >&2
    exit 1
  fi
  expected="$out_dir/$name.svg"
  if [[ ! -f "$expected" ]]; then
    printf 'missing rendered artifact: %s\n' "$expected" >&2
    printf 'refresh with: scripts/diagrams/render-d2.sh\n' >&2
    exit 1
  fi
  if ! diff -u "$expected" "$tmp_dir/$name.svg" >/dev/null; then
    printf 'rendered diagram is stale: %s\n' "$expected" >&2
    printf 'refresh with: scripts/diagrams/render-d2.sh\n' >&2
    exit 1
  fi
done
