#!/usr/bin/env bash

project_tick_run_codex() {
  local actor="$1"
  local prompt_file="$2"
  local result_file="$3"
  local cwd="$4"
  local timeout_seconds="${5:-1500}"
  local runtime_dir="$6"

  mkdir -p "$runtime_dir" "$(dirname "$result_file")"
  local stdout_file="$runtime_dir/last-stdout.txt"
  local stderr_file="$runtime_dir/last-stderr.txt"
  local summary_file="$runtime_dir/last-summary.md"
  local started
  started="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  codex exec \
    --dangerously-bypass-approvals-and-sandbox \
    --cd "$cwd" \
    --output-last-message "$result_file" \
    - < "$prompt_file" > "$stdout_file" 2> "$stderr_file" &

  local pid=$!
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
      {
        echo "# Actor Run"
        echo
        echo "- actor: $actor"
        echo "- status: timeout"
        echo "- started: $started"
        echo "- finished: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "- timeout seconds: $timeout_seconds"
        echo "- prompt: $prompt_file"
        echo "- result: $result_file"
      } > "$summary_file"
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  local status=0
  wait "$pid" || status=$?
  {
    echo "# Actor Run"
    echo
    echo "- actor: $actor"
    echo "- status: $([ "$status" -eq 0 ] && echo complete || echo failed)"
    echo "- exit code: $status"
    echo "- started: $started"
    echo "- finished: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "- prompt: $prompt_file"
    echo "- result: $result_file"
  } > "$summary_file"
  return "$status"
}
