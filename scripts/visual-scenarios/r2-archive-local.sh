#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRY_RUN=()
PRUNE=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=(--dry-run) ;;
    --prune-local) PRUNE=(--prune-local) ;;
    -h|--help)
      cat <<'HELP'
Usage: r2-archive-local.sh [--dry-run] [--prune-local]

Finds top-level capture directories under .meta/multipass/visual-review/ in
every git worktree, uploads each directory's PNGs through r2-sync.sh, and writes
one manifest per capture directory. With --prune-local, only PNGs from
successfully synced directories are removed; notes, status files, command files,
and logs stay local.
HELP
      exit 0
      ;;
    *) echo "Unexpected argument: $1" >&2; exit 64 ;;
  esac
  shift
done

slug() {
  sed -E 's/[^A-Za-z0-9._-]+/-/g; s/-+/-/g; s/^-//; s/-$//' <<<"$1"
}

sync_dir() {
  local worktree="$1"
  local capture_dir="$2"
  local branch dir_name manifest_id args

  branch="$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
  dir_name="$(basename "$capture_dir")"
  manifest_id="archive-$(slug "$branch")-$(slug "$dir_name")"
  printf 'sync %s -> %s\n' "$capture_dir" "$manifest_id"
  args=("$capture_dir" --manifest-id "$manifest_id")
  if [ "${#DRY_RUN[@]}" -gt 0 ]; then args+=("${DRY_RUN[@]}"); fi
  if [ "${#PRUNE[@]}" -gt 0 ]; then args+=("${PRUNE[@]}"); fi
  (
    cd "$worktree"
    "$SCRIPT_DIR/r2-sync.sh" "${args[@]}"
  )
}

while IFS= read -r line; do
  case "$line" in
    worktree\ *) worktree="${line#worktree }" ;;
    "")
      if [ -n "${worktree:-}" ] && [ -d "$worktree/.meta/multipass/visual-review" ]; then
        while IFS= read -r capture_dir; do
          if find "$capture_dir" -maxdepth 1 -type f -name '*.png' -print -quit | grep -q .; then
            sync_dir "$worktree" "$capture_dir"
          fi
        done < <(find "$worktree/.meta/multipass/visual-review" -mindepth 1 -maxdepth 1 -type d | sort)
      fi
      worktree=""
      ;;
  esac
done < <(git -C "$REPO_ROOT" worktree list --porcelain; printf '\n')
