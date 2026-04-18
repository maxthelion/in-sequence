# Important: implementer scope blocks fix-critique on hooks/agents/skills/settings

**Files:** `.claude/agents/implementer.md` lines 18–19 + BT `fix-critique` dispatch
**Severity:** Important

## What's wrong

Implementer scope explicitly forbids editing:

```
.claude/agents/**, .claude/hooks/**, .claude/skills/**, .claude/settings.json, wiki/**
```

But the BT's `fix-critique` action routes every review-queue item to the implementer. Of the three critiques just processed, **all three** targeted forbidden paths (settings.json, a hook, a hook). In this batch I hand-applied them; if the loop were truly autonomous, the implementer would either:

- Report BLOCKED (file stays in queue, stuck loop)
- Obey and edit anyway (silent scope violation, the scope rule is a lie)

Either way the implementer-agent design doesn't compose with fix-critique.

## What would be right

Option A — **path-scoped implementer siblings**:

- `implementer` — Sources/, Tests/ only
- `ops-implementer` — hooks/, settings.json, agents/, skills/, AGENTS.md
- `wiki-implementer` — wiki/ only

BT's `fix-critique` inspects the critique file's `File:` header and routes to the right implementer.

Option B — **relax implementer scope** to "primary scope Sources/Tests; may edit any path IF the critique/work-item explicitly targets it."

Option A is cleaner; Option B is smaller diff. Pick one and stop pretending.

## Acceptance

- A critique targeting a hook routes to a sub-agent that's allowed to edit hooks.
- Agent-file scope language and fix-critique routing agree.
