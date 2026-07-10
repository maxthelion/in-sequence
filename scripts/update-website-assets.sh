#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/update-website-assets.sh --captures [options]
  scripts/update-website-assets.sh --download [--dmg FILE] [options]
  scripts/update-website-assets.sh --all [--dmg FILE] [options]

Updates website-facing R2 pointers/assets from the in-sequence repo.

Modes:
  --captures          Publish the latest absorbed Bug Reporter capture run to the website gallery.
  --download          Upload a DMG and update the website latest-download JSON.
  --all               Run --captures and --download.

Options:
  --dmg FILE          DMG to upload for downloads. Defaults to newest dist/developer-id/*.dmg.
  --build-commit SHA  Commit used to build the DMG. Inferred from a standard DMG filename.
  --build-branch NAME Branch used to build the DMG. Defaults to the current branch.
  --website-dir DIR   Website checkout. Default: ../inseq-website
  --run-id RUN_ID     Capture run to publish. Passed to website gallery:update.
  --min-rows N        Minimum capture rows when selecting latest run. Default: website script default.
  --dry-run           Print planned R2 writes without uploading.
  -h, --help          Show this help.

Notes:
  - Captures are expected to have already been absorbed by /Users/maxwilliams/dev/bug-reporter.
  - Download updates use scripts/r2-upload-artifact.mjs, which writes releases/developer-id/latest.json.
  - To create a new notarized DMG first, run scripts/package-developer-id.sh separately.
USAGE
}

repo_root() {
  git rev-parse --show-toplevel
}

latest_dmg() {
  local root="$1"
  local newest=""
  while IFS= read -r -d '' file; do
    if [[ -z "$newest" || "$file" -nt "$newest" ]]; then
      newest="$file"
    fi
  done < <(find "$root/dist/developer-id" -maxdepth 1 -type f -name '*.dmg' -print0 2>/dev/null)
  printf '%s\n' "$newest"
}

mode=""
dmg=""
build_commit=""
build_branch=""
website_dir=""
run_id=""
min_rows=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --captures)
      mode="captures"
      shift
      ;;
    --download)
      mode="download"
      shift
      ;;
    --all)
      mode="all"
      shift
      ;;
    --dmg)
      dmg="${2:-}"
      shift 2
      ;;
    --build-commit)
      build_commit="${2:-}"
      shift 2
      ;;
    --build-branch)
      build_branch="${2:-}"
      shift 2
      ;;
    --website-dir)
      website_dir="${2:-}"
      shift 2
      ;;
    --run-id)
      run_id="${2:-}"
      shift 2
      ;;
    --min-rows)
      min_rows="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$mode" ]]; then
  echo "Choose --captures, --download, or --all." >&2
  usage >&2
  exit 64
fi

root="$(repo_root)"
if [[ -z "$website_dir" ]]; then
  website_dir="$(cd "$root/.." && pwd)/inseq-website"
fi

if [[ "$mode" == "captures" || "$mode" == "all" ]]; then
  if [[ ! -f "$website_dir/package.json" ]]; then
    echo "Website checkout not found at: $website_dir" >&2
    exit 1
  fi
  capture_command=(npm --prefix "$website_dir" run gallery:update --)
  if [[ -n "$run_id" ]]; then
    capture_command+=(--run-id "$run_id")
  fi
  if [[ -n "$min_rows" ]]; then
    capture_command+=(--min-rows "$min_rows")
  fi
  if [[ "$dry_run" == "1" ]]; then
    capture_command+=(--dry-run)
  fi
  echo "Updating website captures via $website_dir"
  "${capture_command[@]}"
fi

if [[ "$mode" == "download" || "$mode" == "all" ]]; then
  if [[ -z "$dmg" ]]; then
    dmg="$(latest_dmg "$root")"
  fi
  if [[ -z "$dmg" || ! -f "$dmg" ]]; then
    echo "No DMG found. Pass --dmg FILE or create one with scripts/package-developer-id.sh." >&2
    exit 1
  fi
  if [[ -z "$build_commit" && "$(basename "$dmg")" =~ -([0-9a-fA-F]{7,40})-developer-id\.dmg$ ]]; then
    build_commit="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$build_branch" ]]; then
    build_branch="$(git -C "$root" rev-parse --abbrev-ref HEAD)"
  fi
  download_args=(
    "$dmg"
    --bucket in-seq-builds
    --prefix releases/developer-id
    --latest-key releases/developer-id/latest.json
    --branch "$build_branch"
  )
  if [[ -n "$build_commit" ]]; then
    download_args+=(--commit "$build_commit")
  fi
  if [[ "$dry_run" == "1" ]]; then
    download_args+=(--dry-run)
  fi
  echo "Updating website download from $dmg"
  node "$root/scripts/r2-upload-artifact.mjs" "${download_args[@]}"
fi
