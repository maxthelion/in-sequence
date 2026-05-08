#!/usr/bin/env bash
set -euo pipefail
export PROJECT_ACTOR_ID="process-health-observer"
export PROJECT_ACTOR_LABEL="Process Health Observer"
export PROJECT_ACTOR_INBOX="docs/multi-pass-coordinator/inbox/process-health-observer"
export PROJECT_ACTOR_PROMPT="project/actors/process-health-observer/prompt.md"
export PROJECT_ACTOR_ACTIONS="project/actors/process-health-observer/actions.yaml"
exec "$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)/project/actors/_shared/run-inbox-actor.sh" "$@"

