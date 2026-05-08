#!/usr/bin/env bash
set -euo pipefail
export PROJECT_ACTOR_ID="holistic-observer"
export PROJECT_ACTOR_LABEL="Holistic Observer"
export PROJECT_ACTOR_INBOX="docs/multi-pass-coordinator/inbox/holistic-observer"
export PROJECT_ACTOR_PROMPT="project/actors/holistic-observer/prompt.md"
export PROJECT_ACTOR_ACTIONS="project/actors/holistic-observer/actions.yaml"
exec "$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)/project/actors/_shared/run-inbox-actor.sh" "$@"

