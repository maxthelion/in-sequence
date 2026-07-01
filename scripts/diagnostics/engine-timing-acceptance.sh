#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/diagnostics/engine-timing-acceptance.sh start|finish|status|cleanup

start
  Enables AU/sample/timing probes in the sandboxed app preferences, opens the
  latest SequencerAI build, and starts a live unified-log capture.

finish
  Stops the live log capture, runs timing-probe-report, and writes a short
  human acceptance checklist into the capture bundle.

status
  Prints the current capture bundle, app path, log PID, and next manual steps.

cleanup
  Stops any capture started by this script. Does not delete evidence.

Environment:
  SEQUENCER_AI_ACCEPTANCE_ROOT  Evidence root. Default:
                                /tmp/sequencer-ai-engine-timing-acceptance
  SEQUENCER_AI_ACCEPTANCE_BUILD Set to 0 to open without rebuilding.
EOF
  exit 64
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
evidence_root="${SEQUENCER_AI_ACCEPTANCE_ROOT:-/tmp/sequencer-ai-engine-timing-acceptance}"
state_file="${evidence_root}/current.env"
bundle_id="ai.sequencer.SequencerAI"
pref_domain="${HOME}/Library/Containers/${bundle_id}/Data/Library/Preferences/${bundle_id}"
predicate='subsystem == "ai.sequencer.SequencerAI.activity"'
focused_predicate='subsystem == "ai.sequencer.SequencerAI.activity" AND (category == "au-note-trigger" OR category == "sample-trigger" OR category == "timing-probe")'

command="${1:-}"
[[ -n "${command}" ]] || usage

mkdir -p "${evidence_root}"

write_pref() {
  local key="$1"
  defaults write "${pref_domain}" "${key}" -bool YES
}

app_path() {
  if [[ "${SEQUENCER_AI_ACCEPTANCE_BUILD:-1}" == "0" ]]; then
    "${repo_root}/scripts/open-latest-build.sh" --print --no-build
  else
    "${repo_root}/scripts/open-latest-build.sh" --print
  fi
}

print_steps() {
  local bundle="$1"
  cat <<EOF

Engine timing acceptance is capturing evidence in:
  ${bundle}

Manual pass to run now:
  1. In SequencerAI, create or select an AU instrument track.
  2. Press Play once. Confirm whether the AU sounds on that first transport run.
  3. Stop. Confirm Stop does not release a delayed bar of audio.
  4. Create/load the default 808 drum kit.
  5. Press Play once. Confirm kick/snare/hat are all audible immediately.
  6. While running, switch views or interact lightly. Listen for flam, lag, or delayed notes.
  7. Check the mixer meters match what you hear.

When done, run:
  ${repo_root}/scripts/diagnostics/engine-timing-acceptance.sh finish

If you need to see the active bundle again:
  ${repo_root}/scripts/diagnostics/engine-timing-acceptance.sh status
EOF
}

case "${command}" in
  start)
    if [[ -f "${state_file}" ]]; then
      # shellcheck disable=SC1090
      source "${state_file}"
      if [[ -n "${LOG_PID:-}" ]] && kill -0 "${LOG_PID}" 2>/dev/null; then
        printf 'engine-timing-acceptance: capture already running (pid %s)\n' "${LOG_PID}" >&2
        print_steps "${BUNDLE_DIR}"
        exit 0
      fi
    fi

    write_pref AUNoteTraceEnabled
    write_pref SampleTriggerTraceEnabled
    write_pref TimingProbeEnabled

    stamp="$(date +%Y%m%d-%H%M%S)"
    bundle="${evidence_root}/${stamp}"
    mkdir -p "${bundle}"

    resolved_app_path="$(app_path)"
    {
      printf 'started_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'repo=%s\n' "${repo_root}"
      printf 'branch=%s\n' "$(git -C "${repo_root}" branch --show-current 2>/dev/null || printf unknown)"
      printf 'head=%s\n' "$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || printf unknown)"
      printf 'app_path=%s\n' "${resolved_app_path}"
      printf 'prefs=%s\n' "${pref_domain}"
      printf 'predicate=%s\n' "${focused_predicate}"
    } > "${bundle}/manifest.txt"

    /usr/bin/log stream --info --debug --style compact --predicate "${predicate}" > "${bundle}/activity.log" 2> "${bundle}/log-stream.stderr" &
    log_pid="$!"

    cat > "${state_file}" <<EOF
BUNDLE_DIR='${bundle}'
LOG_PID='${log_pid}'
APP_PATH='${resolved_app_path}'
STARTED_AT='${stamp}'
EOF

    open "${resolved_app_path}"
    printf 'engine-timing-acceptance: log stream pid %s\n' "${log_pid}"
    print_steps "${bundle}"
    ;;

  finish)
    if [[ ! -f "${state_file}" ]]; then
      printf 'engine-timing-acceptance: no active capture state at %s\n' "${state_file}" >&2
      exit 1
    fi
    # shellcheck disable=SC1090
    source "${state_file}"
    if [[ -n "${LOG_PID:-}" ]] && kill -0 "${LOG_PID}" 2>/dev/null; then
      kill "${LOG_PID}" 2>/dev/null || true
      sleep 1
    fi

    if [[ ! -d "${BUNDLE_DIR:-}" ]]; then
      printf 'engine-timing-acceptance: bundle missing: %s\n' "${BUNDLE_DIR:-}" >&2
      exit 1
    fi

    log show --last 20m --info --debug --style compact --predicate "${focused_predicate}" > "${BUNDLE_DIR}/focused-last-20m.log" || true
    "${repo_root}/scripts/diagnostics/timing-probe-report.sh" "${BUNDLE_DIR}/activity.log" > "${BUNDLE_DIR}/timing-probe-report.txt" || true

    cat > "${BUNDLE_DIR}/manual-acceptance.md" <<'EOF'
# Engine Timing Manual Acceptance

Fill this in from the human listening pass.

- [ ] AU instrument sounds on the first transport start.
- [ ] Default 808 kit sounds on the first transport start.
- [ ] Kick, snare, and hi-hat are all audible.
- [ ] Stop does not release a delayed bar of audio.
- [ ] No perceptible first-beat flam or double-trigger.
- [ ] Light UI interaction while playing does not create audible lag.
- [ ] Mixer meters match audible output.

## Notes

EOF

    {
      printf 'finished_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'bundle=%s\n' "${BUNDLE_DIR}"
      printf 'activity_log=%s\n' "${BUNDLE_DIR}/activity.log"
      printf 'focused_log=%s\n' "${BUNDLE_DIR}/focused-last-20m.log"
      printf 'timing_report=%s\n' "${BUNDLE_DIR}/timing-probe-report.txt"
      printf 'manual_checklist=%s\n' "${BUNDLE_DIR}/manual-acceptance.md"
    } > "${BUNDLE_DIR}/finished.txt"

    rm -f "${state_file}"
    printf 'engine-timing-acceptance: wrote evidence bundle %s\n' "${BUNDLE_DIR}"
    printf 'Next: edit/review %s with the listening result.\n' "${BUNDLE_DIR}/manual-acceptance.md"
    ;;

  status)
    if [[ ! -f "${state_file}" ]]; then
      printf 'engine-timing-acceptance: no active capture.\n'
      printf 'Start one with:\n  %s/scripts/diagnostics/engine-timing-acceptance.sh start\n' "${repo_root}"
      exit 0
    fi
    # shellcheck disable=SC1090
    source "${state_file}"
    printf 'bundle: %s\n' "${BUNDLE_DIR:-unknown}"
    printf 'app: %s\n' "${APP_PATH:-unknown}"
    printf 'log pid: %s' "${LOG_PID:-unknown}"
    if [[ -n "${LOG_PID:-}" ]] && kill -0 "${LOG_PID}" 2>/dev/null; then
      printf ' (running)\n'
    else
      printf ' (not running)\n'
    fi
    print_steps "${BUNDLE_DIR:-unknown}"
    ;;

  cleanup)
    if [[ -f "${state_file}" ]]; then
      # shellcheck disable=SC1090
      source "${state_file}"
      if [[ -n "${LOG_PID:-}" ]] && kill -0 "${LOG_PID}" 2>/dev/null; then
        kill "${LOG_PID}" 2>/dev/null || true
      fi
      rm -f "${state_file}"
    fi
    printf 'engine-timing-acceptance: cleanup complete\n'
    ;;

  *)
    usage
    ;;
esac
