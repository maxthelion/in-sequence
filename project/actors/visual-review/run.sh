#!/usr/bin/env bash
set -euo pipefail
export PROJECT_ACTOR_ID="visual-review"
export PROJECT_ACTOR_LABEL="Visual Review"
export PROJECT_ACTOR_INBOX="docs/multi-pass-coordinator/inbox/visual-review"
export PROJECT_ACTOR_PROMPT="project/actors/visual-review/prompt.md"
export PROJECT_ACTOR_ACTIONS="project/actors/visual-review/actions.yaml"
exec "$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)/project/actors/_shared/run-inbox-actor.sh" "$@"
