#!/usr/bin/env bash
set -euo pipefail
export PROJECT_ACTOR_ID="testing-review"
export PROJECT_ACTOR_LABEL="Testing Review"
export PROJECT_ACTOR_INBOX="docs/multi-pass-coordinator/inbox/testing"
export PROJECT_ACTOR_PROMPT="project/actors/testing-review/prompt.md"
export PROJECT_ACTOR_ACTIONS="project/actors/testing-review/actions.yaml"
exec "$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)/project/actors/_shared/run-inbox-actor.sh" "$@"
