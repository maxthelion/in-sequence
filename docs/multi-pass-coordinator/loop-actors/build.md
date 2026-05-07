# Build Loop Actor

Handle bounded implementation requests.

Use the worktree, branch, and artifact paths named in the request. If no
worktree is named, either use the current project checkout for very small
coordination-only edits or write a blocker note back to the inbox asking for the
worktree/branch.

Read the relevant plan/spec/handoff before editing code. Run focused tests when
available. Do not merge, push, or touch unrelated worktrees.

If work cannot be safely completed in one actor tick, leave a clear follow-up
request with the next concrete action and evidence still needed.

