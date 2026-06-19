#!/usr/bin/env bash

set -euo pipefail

# macOS does not provide the Linux-style C.UTF-8 locale. Some Codex/CI
# environments still export it, and tools such as shasum invoke Perl, which
# aborts before the helper can print or open the app. Fall back to the portable
# C locale for this script.
if [[ "${LC_ALL:-}" == "C.UTF-8" ]]; then
  export LC_ALL=C
fi
if [[ "${LC_CTYPE:-}" == "C.UTF-8" ]]; then
  export LC_CTYPE=C
fi
if [[ "${LANG:-}" == "C.UTF-8" ]]; then
  export LANG=C
fi

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
git_commit="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
git_branch="$(git -C "${repo_root}" branch --show-current 2>/dev/null || printf 'unknown')"
git_dirty="clean"
if ! git -C "${repo_root}" diff --quiet --ignore-submodules -- 2>/dev/null ||
   ! git -C "${repo_root}" diff --cached --quiet --ignore-submodules -- 2>/dev/null ||
   [[ -n "$(git -C "${repo_root}" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
  git_dirty="dirty"
fi
# Fingerprint the working tree so an unchanged tree can skip the build.
# The attribution timestamp below changes per invocation; passing it to
# xcodebuild unconditionally invalidated the previous build every time,
# which is why this script always recompiled.
content_fingerprint="${git_commit}-$(
  {
    git -C "${repo_root}" diff HEAD 2>/dev/null
    git -C "${repo_root}" ls-files --others --exclude-standard 2>/dev/null \
      | while IFS= read -r f; do stat -f '%N %m %z' "${repo_root}/${f}" 2>/dev/null; done
  } | shasum | cut -c1-12
)"

manifest_dir="${repo_root}/.meta/multipass/runtime/build-attribution"
latest_manifest="$(ls -t "${manifest_dir}"/*.json 2>/dev/null | head -n 1 || true)"

build_attribution_version="$(date -u +%Y%m%d%H%M%S)"
build_attribution_id="${git_commit}-${git_dirty}-${build_attribution_version}"

if [[ "${build_before_open}" == "yes" && -n "${latest_manifest}" ]] && command -v jq >/dev/null; then
  previous_fingerprint="$(jq -r '.contentFingerprint // empty' "${latest_manifest}" 2>/dev/null || true)"
  previous_app_path="$(jq -r '.appPath // empty' "${latest_manifest}" 2>/dev/null || true)"
  if [[ -n "${previous_fingerprint}" && "${previous_fingerprint}" == "${content_fingerprint}" && -d "${previous_app_path}" ]]; then
    # Exact content already built: reuse it (and its embedded attribution)
    # instead of re-stamping, which would force a rebuild for nothing.
    build_before_open="no"
    build_attribution_version="$(jq -r '.buildVersion' "${latest_manifest}")"
    build_attribution_id="$(jq -r '.attributionID' "${latest_manifest}")"
    echo "open-latest-build: tree unchanged since ${build_attribution_id}; skipping build" >&2
  fi
fi

build_metadata_settings=(
  "BUILD_ATTRIBUTION_ID=${build_attribution_id}"
  "BUILD_ATTRIBUTION_VERSION=${build_attribution_version}"
  "GIT_COMMIT=${git_commit}"
  "GIT_BRANCH=${git_branch}"
  "GIT_DIRTY=${git_dirty}"
)

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
    "${build_metadata_settings[@]}" \
    build >/dev/null
fi

build_settings="$(
  xcodebuild_filtered \
    -project "${project_path}" \
    -scheme "${scheme_name}" \
    -destination "${destination}" \
    "${build_metadata_settings[@]}" \
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

if [[ "${build_before_open}" == "yes" ]]; then
  manifest_path="${manifest_dir}/${build_attribution_version}.json"
  mkdir -p "${manifest_dir}"
  jq -n \
    --arg attributionID "${build_attribution_id}" \
    --arg buildVersion "${build_attribution_version}" \
    --arg gitCommit "${git_commit}" \
    --arg gitBranch "${git_branch}" \
    --arg gitDirty "${git_dirty}" \
    --arg contentFingerprint "${content_fingerprint}" \
    --arg appPath "${app_path}" \
    --arg builtAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      attributionID: $attributionID,
      buildVersion: $buildVersion,
      gitCommit: $gitCommit,
      gitBranch: $gitBranch,
      gitDirty: $gitDirty,
      contentFingerprint: $contentFingerprint,
      appPath: $appPath,
      builtAt: $builtAt
    }' > "${manifest_path}"
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
