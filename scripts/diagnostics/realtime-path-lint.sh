#!/usr/bin/env bash
set -euo pipefail

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
  printf 'realtime path lint requires ripgrep (rg); set RG_BIN to its path\n' >&2
  exit 127
fi

if (($# > 0)); then
  files=("$@")
else
  files=(
    "Sources/Engine/EngineController.swift"
    "Sources/Engine/EngineControllerAudioInput.swift"
    "Sources/Engine/EngineControllerNoteRepeat.swift"
    "Sources/Engine/EngineSlicerDispatcher.swift"
    "Sources/Engine/RouterDispatchState.swift"
    "Sources/Audio/MainAudioGraph.swift"
    "Sources/Audio/AudioInstrumentHost.swift"
    "Sources/Audio/SamplerFilterNode.swift"
    "Sources/Audio/SamplePlaybackEngine.swift"
  )
fi

base_forbidden_regex='(AudioFileRef\.resolve|\.fileRef\.resolve|AVAudioFile\(forReading:|FileManager\.default|Data\(contentsOf:|DispatchQueue\.main\.sync|MainActor\.run|Task[[:space:]]*\{[[:space:]]*@MainActor)'
graph_mutation_regex='((^|[^A-Za-z0-9_])audioGraph\.(attach|detach|connect|disconnectOutput|disconnectInput)\(|(^|[^A-Za-z0-9_])engine\.(attach|detach|connect|disconnectNodeOutput|disconnectNodeInput)\(|(^|[^A-Za-z0-9_])reconnect[A-Za-z0-9_]*\()'
default_forbidden_regex="(${base_forbidden_regex}|${graph_mutation_regex})"
failed=0
allow_regex='realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+'

for file in "${files[@]}"; do
  if [[ "$file" = /* ]]; then
    path="$file"
  else
    path="$repo_root/$file"
  fi

  forbidden_regex="$default_forbidden_regex"
  case "$file" in
    */MainAudioGraph.swift|Sources/Audio/MainAudioGraph.swift)
      # MainAudioGraph is the graph owner. Its graph mutations are the owned
      # implementation surface, but it is still linted for file IO and main
      # hops so permissions-sensitive/audio-thread regressions stay visible.
      forbidden_regex="$base_forbidden_regex"
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
    printf '%s:%s: realtime path uses forbidden API: %s\n' "$file" "$line" "$text" >&2
    failed=1
  done < <("$rg_bin" -n "$forbidden_regex" "$path" || true)

  while IFS=: read -r line text; do
    [[ -z "${line:-}" ]] && continue
    if [[ ! "$text" =~ $allow_regex ]]; then
      printf '%s:%s: realtime allow annotation must include a reason and Test: reference: %s\n' "$file" "$line" "$text" >&2
      failed=1
    fi
  done < <("$rg_bin" -n 'realtime-allow-' "$path" || true)

  awk -v file="$file" '
    function has_allow(line) {
      return line ~ /realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+/
    }
    /DispatchQueue\.main\.async/ {
      if (!has_allow($0) && !has_allow(previous)) {
        printf "%s:%d: realtime path uses unannotated DispatchQueue.main.async: %s\n", file, NR, $0 > "/dev/stderr"
        failed = 1
      }
    }
    { previous = $0 }
    END { exit failed ? 1 : 0 }
  ' "$path" || failed=1
done

exit "$failed"
