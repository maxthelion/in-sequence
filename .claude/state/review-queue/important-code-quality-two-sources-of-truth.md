# Important: code-quality-reviewer cites two "built on" sources that can drift

**File:** `.claude/agents/code-quality-reviewer.md`, lines 10–12
**Severity:** Important

## What's wrong

The "Built on" section cites two upstream sources:

```
- `~/.claude/plugins/.../superpowers/.../agents/code-reviewer.md` (SOLID, patterns)
- `~/.claude/plugins/.../subagent-driven-development/code-quality-reviewer-prompt.md`
  (responsibility, decomposition, file-size growth)
```

If the two drift (the plugin cache updates; the superpowers version changes), the agent has to reconcile two different rubrics silently. There's no single canonical source.

## What would be right

Pick one as the canonical upstream; cite the other as "see also":

```
## Built on

The generic code-quality rubric is the superpowers `code-reviewer` agent at
`~/.claude/plugins/.../agents/code-reviewer.md`. Apply that; then layer on
the project-specific items below.

See also `subagent-driven-development/code-quality-reviewer-prompt.md` for
responsibility-and-file-size emphasis — same spirit, different angle.
```

Alternatively, inline the specific points from the second source into the project-specific deltas section (file-size growth check, responsibility decomposition) so the upstream reference isn't load-bearing.

## Acceptance

- Agent file has one authoritative upstream source; any additional references are "see also."
