#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'EOF'
scripts/roadmap/promote-ready-item-to-worktree.sh is retired.

The old script promoted roadmap items into a Claude behaviour-tree worktree and
then instructed agents to run /loop /next-action. That control path has been
removed.

Use the Multi-Pass project loop instead:

  1. Let feature-readiness-observer observe ready roadmap artifacts.
  2. Let the project orienter interpret readiness, build capacity, and priority.
  3. Let the project decider promote a feature into a build loop.

For a manual promotion, use the central runtime:

  bun /Users/maxwilliams/dev/multi-pass-coordinator/src/cli/promote-build.ts \
    --project /Users/maxwilliams/dev/in-sequence \
    --feature <feature-slug> \
    --worktree .worktrees/<feature-worktree> \
    --branch auto/<feature-branch>
EOF

exit 1
