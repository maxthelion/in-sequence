#!/usr/bin/env bash
set -euo pipefail
export PROJECT_ACTOR_ID="work-observer"
export PROJECT_ACTOR_LABEL="Work Observer"
export PROJECT_ACTOR_INBOX="docs/multi-pass-coordinator/inbox/work-observer"
export PROJECT_ACTOR_PROMPT="project/actors/work-observer/prompt.md"
export PROJECT_ACTOR_ACTIONS="project/actors/work-observer/actions.yaml"
exec "$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)/project/actors/_shared/run-inbox-actor.sh" "$@"

