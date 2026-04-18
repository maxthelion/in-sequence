#!/usr/bin/env bash

set -euo pipefail

mode="open"
if [[ "${1:-}" == "--print" ]]; then
  mode="print"
elif [[ "${1:-}" == "--reveal" ]]; then
  mode="reveal"
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--print|--reveal]" >&2
  exit 64
fi

derived_data_root="${HOME}/Library/Developer/Xcode/DerivedData"
app_name="SequencerAI.app"

if [[ ! -d "${derived_data_root}" ]]; then
  echo "DerivedData not found at ${derived_data_root}" >&2
  exit 1
fi

latest_app="$(
  find "${derived_data_root}" \
    -path "*/Build/Products/Debug/${app_name}" \
    -type d \
    -print0 \
    | xargs -0 stat -f '%m %N' \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2-
)"

if [[ -z "${latest_app}" ]]; then
  echo "No Debug build found for ${app_name}. Run xcodebuild test or build first." >&2
  exit 1
fi

case "${mode}" in
  print)
    printf '%s\n' "${latest_app}"
    ;;
  reveal)
    open -R "${latest_app}"
    ;;
  open)
    open "${latest_app}"
    ;;
esac
