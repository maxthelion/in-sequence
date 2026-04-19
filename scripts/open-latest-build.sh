#!/usr/bin/env bash

set -euo pipefail

mode="open"
build_before_open="yes"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --print)
      mode="print"
      build_before_open="no"
      ;;
    --reveal)
      mode="reveal"
      build_before_open="no"
      ;;
    --no-build)
      build_before_open="no"
      ;;
    *)
      echo "usage: $0 [--print|--reveal] [--no-build]" >&2
      exit 64
      ;;
  esac
  shift
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
project_path="${repo_root}/SequencerAI.xcodeproj"
scheme_name="SequencerAI"

if [[ ! -d "${project_path}" ]]; then
  echo "Project not found at ${project_path}" >&2
  exit 1
fi

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
destination="platform=macOS,arch=arm64"

xcodebuild_filtered() {
  DEVELOPER_DIR="${developer_dir}" \
    xcodebuild "$@" 2> >(
      awk '
        /^--- xcodebuild: WARNING: Using the first of multiple matching destinations:/ { skip=1; next }
        skip && /^\{ platform:macOS/ { next }
        { skip=0; print > "/dev/stderr" }
      '
    )
}

if [[ "${build_before_open}" == "yes" ]]; then
  xcodebuild_filtered \
    -project "${project_path}" \
    -scheme "${scheme_name}" \
    -destination "${destination}" \
    build >/dev/null
fi

build_settings="$(
  xcodebuild_filtered \
    -project "${project_path}" \
    -scheme "${scheme_name}" \
    -destination "${destination}" \
    -showBuildSettings
)"

target_build_dir="$(printf '%s\n' "${build_settings}" | sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p' | head -n 1)"
full_product_name="$(printf '%s\n' "${build_settings}" | sed -n 's/^[[:space:]]*FULL_PRODUCT_NAME = //p' | head -n 1)"

if [[ -z "${target_build_dir}" || -z "${full_product_name}" ]]; then
  echo "Could not resolve build output path from xcodebuild settings." >&2
  exit 1
fi

app_path="${target_build_dir}/${full_product_name}"

if [[ ! -d "${app_path}" ]]; then
  echo "Build product not found at ${app_path}" >&2
  exit 1
fi

case "${mode}" in
  print)
    printf '%s\n' "${app_path}"
    ;;
  reveal)
    open -R "${app_path}"
    ;;
  open)
    open "${app_path}"
    ;;
esac
