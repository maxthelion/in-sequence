#!/usr/bin/env bash
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
repo_root="${ROOT_DIR:-$(cd "$(dirname "$script_path")/../.." && pwd)}"
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
  printf 'runtime ownership lint requires ripgrep (rg); set RG_BIN to its path\n' >&2
  exit 127
fi

if [[ "${1:-}" == "--self-test" ]]; then
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/runtime-ownership-lint.XXXXXX")"
  trap 'rm -rf "$tmp_root"' EXIT
  mkdir -p "$tmp_root/Sources/Engine" "$tmp_root/Sources/Audio"
  cat > "$tmp_root/Sources/Engine/EngineController.swift" <<'FIXTURE'
import SwiftUI
final class EngineController {
    let session: SequencerDocumentSession? = nil
}
FIXTURE
  touch \
    "$tmp_root/Sources/Engine/EngineControllerRoutingHelpers.swift" \
    "$tmp_root/Sources/Engine/EngineSlicerDispatcher.swift" \
    "$tmp_root/Sources/Engine/EngineControllerNoteRepeat.swift" \
    "$tmp_root/Sources/Engine/EventQueue.swift" \
    "$tmp_root/Sources/Engine/TickClock.swift" \
    "$tmp_root/Sources/Engine/TickStateBuffer.swift"
  cat > "$tmp_root/Sources/Audio/SamplePlaybackEngine.swift" <<'FIXTURE'
import AVFoundation
func bad(url: URL) throws {
    _ = try AVAudioFile(forReading: url)
}
FIXTURE
  cat > "$tmp_root/Sources/Audio/AudioGraphFixture.swift" <<'FIXTURE'
final class AudioGraphFixture {
    var session: SequencerDocumentSession?
}
FIXTURE

  set +e
  output="$(ROOT_DIR="$tmp_root" "$script_path" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'runtime ownership lint self-test failed: seeded violations passed\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  if [[ "$output" != *"Engine hot/runtime files must not import UI frameworks"* ||
        "$output" != *"Sample/slicer trigger paths contain unannotated file IO"* ||
        "$output" != *"Audio graph/cache files must not reach document/session owners directly"* ]]; then
    printf 'runtime ownership lint self-test failed: expected diagnostics missing\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  printf 'runtime ownership lint self-test passed\n'
  exit 0
fi

failures=0

report_match() {
  local title="$1"
  local output="$2"
  if [[ -n "$output" ]]; then
    printf '%s\n%s\n' "$title" "$output" >&2
    failures=1
  fi
}

engine_imports="$("$rg_bin" -n '^\s*import\s+(SwiftUI|AppKit)\b' "$repo_root/Sources/Engine" || true)"
report_match "Engine hot/runtime files must not import UI frameworks:" "$engine_imports"

main_only_in_tick="$("$rg_bin" -n '\b(SequencerDocumentSession|LiveSequencerStore(State)?|NSView|NSWindow|ViewBuilder)\b' \
  "$repo_root/Sources/Engine/EngineController.swift" \
  "$repo_root/Sources/Engine/EngineControllerRoutingHelpers.swift" \
  "$repo_root/Sources/Engine/EngineSlicerDispatcher.swift" \
  "$repo_root/Sources/Engine/EngineControllerNoteRepeat.swift" \
  "$repo_root/Sources/Engine/EventQueue.swift" \
  "$repo_root/Sources/Engine/TickClock.swift" \
  "$repo_root/Sources/Engine/TickStateBuffer.swift" || true)"
report_match "Tick/dispatch hot files reference main-only UI/session owners:" "$main_only_in_tick"

allow_regex='realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+'
file_io_regex='\b(FileManager\.default|AVAudioFile\s*\(|Data\s*\(\s*contentsOf:|contentsOfFile:)\b'
file_io_files=(
  "$repo_root/Sources/Engine/EngineController.swift"
  "$repo_root/Sources/Engine/EngineControllerRoutingHelpers.swift"
  "$repo_root/Sources/Engine/EngineSlicerDispatcher.swift"
  "$repo_root/Sources/Audio/SamplePlaybackEngine.swift"
)
unannotated_file_io=""
for path in "${file_io_files[@]}"; do
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
    unannotated_file_io+="${path#$repo_root/}:$line:$text"$'\n'
  done < <("$rg_bin" -n "$file_io_regex" "$path" || true)
done
report_match "Sample/slicer trigger paths contain unannotated file IO:" "$unannotated_file_io"

session_from_audio="$("$rg_bin" -n '\b(SequencerDocumentSession|LiveSequencerStore|ProjectDocument|SeqAIDocument)\b' "$repo_root/Sources/Audio" || true)"
report_match "Audio graph/cache files must not reach document/session owners directly:" "$session_from_audio"

bad_allow="$("$rg_bin" -n 'realtime-allow-' "$repo_root/Sources" | awk '
  $0 !~ /realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+/ {
    print
  }
' || true)"
report_match "Realtime allow annotations must include a reason and Test reference:" "$bad_allow"

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi
