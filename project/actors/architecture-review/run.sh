#!/usr/bin/env bash
set -euo pipefail
export PROJECT_ACTOR_ID="architecture-review"
export PROJECT_ACTOR_LABEL="Architecture Review"
export PROJECT_ACTOR_INBOX="docs/multi-pass-coordinator/inbox/architecture"
export PROJECT_ACTOR_PROMPT="project/actors/architecture-review/prompt.md"
export PROJECT_ACTOR_ACTIONS="project/actors/architecture-review/actions.yaml"
exec "$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)/project/actors/_shared/run-inbox-actor.sh" "$@"
