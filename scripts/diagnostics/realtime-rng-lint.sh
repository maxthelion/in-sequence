#!/usr/bin/env bash
set -euo pipefail

# realtime-rng-lint — the MISSING Phase-2 gate.
#
# The spec (docs/plans/2026-06-30-precompute-lookahead-recording.md, Phase 2,
# line 101) states the executable gate:
#
#     "realtime-path-lint shows no RNG/alloc on the tick path"
#
# But realtime-path-lint.sh never contained any RNG/allocation check (it scans
# file IO, main hops, graph mutation, wall-clock timing, and disk reads). That
# gate was therefore vaporware: the equivalence rail
# (PrecomputeBarEquivalenceTests) only tests `BarPrecomputeEvaluator.precompute`
# in isolation, and nothing asserts that the TICK PATH actually consumes a
# `PrecomputedBar` instead of generating live. So `EngineController.prepareTick`
# can keep allocating a fresh `SystemRandomNumberGenerator()` per (track, tick)
# and calling `resolvedStepNotes` live — the whole point of Phase 2 — while
# every gate stays green.
#
# This lint closes that hole deterministically: on the realtime tick/prepare
# path, a fresh per-tick RNG construction (`SystemRandomNumberGenerator()`) is
# the live-generation signature Phase 2 must remove. Generation must move OFF
# the tick path; the tick path consumes a precomputed bar (a pure dictionary
# read). Any `SystemRandomNumberGenerator(` on the tick-path files fails this
# lint UNLESS annotated `realtime-allow-<reason>: <classification> . Test:
# <name>` (same opt-out grammar as realtime-path-lint).
#
# Authored as a SEPARATE script (not an edit to the frozen realtime-path-lint.sh)
# so it touches no frozen rail. This is the standing defense the spec's Phase-7
# distill calls for ("a new ... conformity check joins ... realtime-path-lint").

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rg_bin="${RG_BIN:-$(command -v rg || true)}"
if [[ -z "$rg_bin" ]]; then
  for candidate in \
    "/Applications/Codex.app/Contents/Resources/rg" \
    "/opt/homebrew/bin/rg" \
    "/usr/local/bin/rg"
  do
    if [[ -x "$candidate" ]]; then
      rg_bin="$candidate"
      break
    fi
  done
fi

if [[ -z "$rg_bin" ]]; then
  printf 'realtime rng lint requires ripgrep (rg); set RG_BIN to its path\n' >&2
  exit 127
fi

if (($# > 0)); then
  files=("$@")
else
  # The tick / prepare / scheduling path. Generation runs here today and must
  # move OFF it in Phase 2.
  files=(
    "Sources/Engine/EngineController.swift"
    "Sources/Engine/EngineControllerNoteRepeat.swift"
    "Sources/Engine/EngineSlicerDispatcher.swift"
    "Sources/Engine/RouterDispatchState.swift"
  )
fi

# A per-tick live RNG construction — the live-generation signature Phase 2 moves
# off the tick path. Constructing a system RNG per tick is also a realtime
# allocation, which the Audio Engine Hard Rules forbid on the render/tick path.
forbidden_regex='SystemRandomNumberGenerator\('
allow_regex='realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+'
failed=0

for file in "${files[@]}"; do
  if [[ "$file" = /* ]]; then
    path="$file"
  else
    path="$repo_root/$file"
  fi
  [[ -e "$path" ]] || continue

  # Scope the RNG rule to the tick/prepare/scheduling files by basename — same
  # filename-scoping the existing realtime-path-lint Rule blocks use — so a
  # `SystemRandomNumberGenerator()` in an unrelated file (e.g. UI, audition
  # preview) is not the tick path this gate guards. When an explicit file
  # argument is passed, it is still scoped by its basename.
  case "$file" in
    */EngineController.swift|Sources/Engine/EngineController.swift \
    |*/EngineControllerNoteRepeat.swift|Sources/Engine/EngineControllerNoteRepeat.swift \
    |*/EngineSlicerDispatcher.swift|Sources/Engine/EngineSlicerDispatcher.swift \
    |*/RouterDispatchState.swift|Sources/Engine/RouterDispatchState.swift)
      : # in scope — fall through to the checks below
      ;;
    *)
      continue
      ;;
  esac

  while IFS=: read -r line text; do
    [[ -z "${line:-}" ]] && continue
    [[ "$text" =~ ^[[:space:]]*// ]] && continue
    previous=""
    if (( line > 1 )); then
      previous="$(sed -n "$((line - 1))p" "$path")"
    fi
    if [[ "$text" =~ $allow_regex || "$previous" =~ $allow_regex ]]; then
      continue
    fi
    printf '%s:%s: Phase 2 violated: live RNG construction on the tick/prepare path — generation must move OFF the tick path (consume a PrecomputedBar), the tick path must do a pure dictionary read with no RNG/alloc; off-tick generation seams must be annotated `// realtime-allow-<reason>: <classification> . Test: <name>`: %s\n' "$file" "$line" "$text" >&2
    failed=1
  done < <("$rg_bin" -n "$forbidden_regex" "$path" || true)

  while IFS=: read -r line text; do
    [[ -z "${line:-}" ]] && continue
    if [[ ! "$text" =~ $allow_regex ]]; then
      printf '%s:%s: realtime allow annotation must include a reason and Test: reference: %s\n' "$file" "$line" "$text" >&2
      failed=1
    fi
  done < <("$rg_bin" -n 'realtime-allow-' "$path" || true)
done

exit "$failed"
