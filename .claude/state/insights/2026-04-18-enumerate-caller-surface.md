# Meta-pattern from 2026-04-18 adversarial review

From the review of `72d6a6c..d82ea2d` (automation hygiene batch).

## The pattern

**"Declare a structure in docs/config, but wire up only half the callers."**

Every finding in this batch matched the same shape:

- New agent roster exists, but `/execute-plan` still dispatches to generic targets. Half-wired.
- `deny` list added, but covers only `-D` / `-d` / `-d`; misses `--delete`, `-Df`, `update-ref -d`, `push : remote`. Half-wired.
- Scanner boundary set covers `;|&(){}`; misses `` ` `` / `\n` / heredocs / `eval` / `command` / `exec`. Half-wired.
- Test harness asserts FIRE/SKIP but not rest-args. Half-wired.
- `blocked/` subdir convention mentioned in comments; nothing moves items in/out. Half-wired.
- Two docs list the per-action agent/model; no single canon. Half-wired (at scale: it'll drift).

## The checklist entry

When adding any new mechanism (rule, config, allowlist/denylist, operator set, agent roster, table of dispatches), **enumerate the full surface of callers and sibling cases in a single table before closing.** Make the test *the table*, not a sample from it.

Examples:

- **Deny list** → table rows = every flag spelling (short, long, combined, plumbing equivalent). Assert each is denied.
- **Operator-aware parser** → table rows = every shell metacharacter, redirector, and builtin. Assert each is handled or explicitly out of scope.
- **Agent roster** → table rows = every caller skill × every agent. Assert each caller dispatches the right agent.
- **Convention in a subdir** → table rows = who moves items in / who moves items out / who reads them. If any row is empty, either wire it or drop the convention.

## Proposed code-review-checklist update

Add a new §5 or bullet under §2:

> **§ Enumerate the surface**
>
> When you introduce a new mechanism (config rule, parser, roster, dispatch table), list the full surface of callers and sibling cases in a single structure before closing. The test should *be* the structure (one row per case), not a sample of it. Half-wiring — where the mechanism works for the case you were thinking about but misses adjacent cases — is the top source of adversarial findings in this project.

## Where this came from

Adversarial review dispatched from `/next-action` → `adversarial-review` skill, 2026-04-18, against the 12-commit automation hygiene batch. See `.claude/state/review-queue/critical-*.md` for the specific findings.
