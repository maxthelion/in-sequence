#!/usr/bin/env bash

set -euo pipefail

minutes="${1:-180}"

if ! [[ "${minutes}" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 [minutes]" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
diagnostic_dir="${HOME}/Library/Logs/DiagnosticReports"
manifest_dir="${repo_root}/.meta/multipass/runtime/build-attribution"
cutoff_epoch="$(($(date +%s) - (minutes * 60)))"

echo "# SequencerAI Runtime Log Scan"
echo
echo "- scanned_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "- window_minutes: ${minutes}"
echo "- diagnostic_reports: ${diagnostic_dir}"
echo "- attribution_manifests: ${manifest_dir}"
echo

echo "## Crash Reports"
echo

report_count=0
while IFS= read -r report; do
  [[ -n "${report}" ]] || continue
  report_count=$((report_count + 1))

  echo "### ${report}"
  echo

  capture_time="$(jq -r 'select(.procPath? != null) | .captureTime // "unknown"' "${report}" | tail -1)"
  proc_path="$(jq -r 'select(.procPath? != null) | .procPath // "unknown"' "${report}" | tail -1)"
  bundle_version="$(jq -r 'select(.procPath? != null) | .bundleInfo.CFBundleVersion // "unknown"' "${report}" | tail -1)"
  app_version="$(jq -r 'select(.procPath? != null) | .bundleInfo.CFBundleShortVersionString // "unknown"' "${report}" | tail -1)"
  exception="$(jq -r 'select(.procPath? != null) | .exception.signal // .exception.type // "unknown"' "${report}" | tail -1)"
  termination="$(jq -r 'select(.procPath? != null) | .termination.indicator // "unknown"' "${report}" | tail -1)"

  echo "- capture_time: ${capture_time}"
  echo "- app_version: ${app_version}"
  echo "- crash_bundle_version: ${bundle_version}"
  echo "- exception: ${exception}"
  echo "- termination: ${termination}"
  echo "- proc_path: ${proc_path}"

  manifest_path="${manifest_dir}/${bundle_version}.json"
  if [[ -f "${manifest_path}" ]]; then
    echo "- attribution_manifest: ${manifest_path}"
    jq -r '"- attribution: commit=\(.gitCommit) branch=\(.gitBranch) dirty=\(.gitDirty) id=\(.attributionID) builtAt=\(.builtAt)"' "${manifest_path}"
  else
    echo "- attribution_manifest: missing"
  fi

  echo
  echo "Top app frames:"
  jq -r '
    select(.procPath? != null)
    | (.lastExceptionBacktrace // [])
    | map(select(type == "object"))
    | map(select((.sourceFile // "") != "" or (.symbol // "") != ""))
    | .[:18][]
    | "- \((.sourceFile // "system")):\((.sourceLine // "-") | tostring) \(.symbol // "")"
  ' "${report}" | sed '/^- system:- $/d'
  echo
done < <(
  if [[ -d "${diagnostic_dir}" ]]; then
    find "${diagnostic_dir}" -maxdepth 1 -type f \( -name 'SequencerAI*.ips' -o -name 'SequencerAI*.crash' \) -print0 |
      while IFS= read -r -d '' file; do
        modified="$(stat -f %m "${file}")"
        if (( modified >= cutoff_epoch )); then
          printf '%s\t%s\n' "${modified}" "${file}"
        fi
      done |
      sort -nr |
      cut -f2-
  fi
)

if (( report_count == 0 )); then
  echo "No recent SequencerAI crash reports found."
  echo
fi

echo "## Recent Launch Metadata"
echo
if /usr/bin/log show --last "${minutes}m" --style compact \
  --predicate 'process == "SequencerAI" AND eventMessage CONTAINS[c] "[SequencerAIAppDelegate] launch"' 2>/dev/null; then
  true
else
  echo "Launch metadata query failed."
fi

echo
echo "## Recent Fatal/AVAudio Signals"
echo
if /usr/bin/log show --last "${minutes}m" --style compact \
  --predicate 'process == "SequencerAI" AND (eventMessage CONTAINS[c] "AVAudio" OR eventMessage CONTAINS[c] "fatal" OR eventMessage CONTAINS[c] "abort" OR eventMessage CONTAINS[c] "exception" OR eventMessage CONTAINS[c] "required condition")' 2>/dev/null; then
  true
else
  echo "Fatal signal query failed."
fi
