# Minor: model/agent roster described in two places with drift risk

**Files:**
- `AGENTS.md` § "Per-action subagent configuration" (roster table at line ~124)
- `.claude/skills/next-action/SKILL.md` action table (lines ~47–58)

**Severity:** Minor

## What's wrong

Both files document the per-action agent and model choice. They agree today; they will drift. This is the classic docs-as-canon-duplication anti-pattern.

## What would be right

Pick one as canon, reduce the other to a link:

- **Option A:** `AGENTS.md` is canonical (primary agent docs). The next-action SKILL.md action table drops the agent/model column and references AGENTS.md: "Agent and model choice → see `AGENTS.md` § Per-action subagent configuration."
- **Option B:** SKILL.md is canonical (BT-specific). AGENTS.md § Per-action subagent configuration links out.

Option A is cleaner because AGENTS.md is the per-role authoritative doc; SKILL.md is operational instructions.

## Acceptance

- Only one of the two docs enumerates per-action model+agent. The other links.
