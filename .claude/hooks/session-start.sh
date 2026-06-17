#!/usr/bin/env bash
# SessionStart hook. Emits a compact status banner for the current Multi-Pass
# OODA model. This is orientation only; it does not schedule work.
set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO"

if LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null)" && [ -n "$LAST_TAG" ]; then
  AHEAD="$(git rev-list --count "$LAST_TAG"..HEAD 2>/dev/null || echo '?')"
  TAG_LINE="last tag: $LAST_TAG   +$AHEAD commits"
else
  AHEAD="$(git rev-list --count HEAD 2>/dev/null || echo '?')"
  TAG_LINE="history:  $AHEAD commits (untagged)"
fi

DIRTY=""
[ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=" (dirty)"

PENDING=0
if [ -d ".meta/multipass/runtime/inbox/pending" ]; then
  PENDING="$(find .meta/multipass/runtime/inbox/pending -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
fi

BUILD_LOOPS="none"
if [ -d ".meta/multipass/config/loops/build" ]; then
  BUILD_LOOPS="$(
    find .meta/multipass/config/loops/build -maxdepth 1 -type f -name '*.yaml' 2>/dev/null \
      | sed 's#.*/##; s#\.yaml$##' \
      | sort \
      | paste -sd ', ' -
  )"
  [ -n "$BUILD_LOOPS" ] || BUILD_LOOPS="none"
fi

cat <<EOF
in-sequence status
  $TAG_LINE$DIRTY
  automation: Multi-Pass v2 / OODA
  loops:      project + build[$BUILD_LOOPS]
  inbox:      $PENDING pending runtime message(s)
  tick:       project/scripts/tick.sh --write
  inventory:  bun /Users/maxwilliams/dev/multi-pass-coordinator/src/cli/inventory.ts --project "$REPO"
EOF
