#!/usr/bin/env bash
set -euo pipefail
export PROJECT_ACTOR_ID="process-fixer"
export PROJECT_ACTOR_LABEL="Process Fixer"
export PROJECT_ACTOR_INBOX="project/actors/process-fixer/inbox"
export PROJECT_ACTOR_PROMPT="project/actors/process-fixer/prompt.md"
export PROJECT_ACTOR_ACTIONS="project/actors/process-fixer/actions.yaml"
exec "$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)/project/actors/_shared/run-inbox-actor.sh" "$@"
