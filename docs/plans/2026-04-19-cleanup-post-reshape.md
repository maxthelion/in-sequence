# Cleanup Plan — Post-Reshape Drift

> **Status:** DRAFT — rescued from chat transcript 2026-04-19. Needs fleshing out with the actual 10-step cleanup list from the adversarial-review output that prompted it.

**Goal:** Finish what `track-group-reshape` started — migrate or delete every remaining reader of the prior representation so the old shapes genuinely disappear, rather than living alongside the new ones. Source: adversarial review of the reshape identified 10+ drift findings (duplicate types, readers of legacy shapes, etc.) that were deliberately deferred.

**Architecture:** Pure cleanup. No new subsystems. Per-finding: locate all call-sites, migrate to new representation, delete the old path. The meta-rule being enforced: *a reshape plan is not complete until every reader of the prior representation is migrated or deleted. Adding new types alongside old ones and letting later plans "clean up" is the #1 source of drift.*

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`. Follow-up to `docs/plans/2026-04-19-track-group-reshape.md`.

**Depends on:**
- `track-group-reshape` completed and tagged
- `characterization` plan completed — goldens in place to catch accidental behaviour changes during cleanup
- Ideally the build-breaker (TrackGroup duplicate declaration, C1 from review) fixed first

**Status:** Not started. No tag allocated yet.

---

## Findings to address (from adversarial review)

> **TODO:** populate this section from the adversarial-review output of the reshape commits. The transcript references "10-step cleanup list" but the actual list wasn't preserved. Re-run `/adversarial-review` against the reshape range (`99baf52..f040e48`) or recover the original review-queue entries to repopulate.

Known drift-classes to look for (from the transcript context):

1. Duplicate top-level type declarations across files (e.g. `TrackGroup` declared in multiple places — would be caught by the pre-commit hook in the characterization plan's Task 8).
2. Readers of the prior `track.instrumentRef` / `track.drumRackRef` shapes still present after the flat-`destination` refactor.
3. Legacy `.drumRack` track-type references that should migrate to the new 3-case enum.
4. Orphan code paths — code that no longer executes but wasn't deleted.
5. Wiki-code drift — wiki pages describing the old shape.

---

## Tasks (to be written)

- [ ] Task 1: Run adversarial-review against the reshape range; capture all findings
- [ ] Task 2: Triage findings into categories (migrate / delete / defer-with-reason)
- [ ] Task 3–N: One task per category, fix-critique dispatched
- [ ] Final task: verify characterization goldens unchanged (or update with `chore(golden):` commits if behaviour deliberately changed)
- [ ] Tag `v0.0.12-cleanup-post-reshape` (assuming characterization takes v0.0.11)

---

## Open questions

- Should this plan be written DETERMINISTICALLY now (by re-running adversarial-review) or wait for the characterization goldens to be in place so fixes can be verified mechanically? Recommended: wait — the goldens turn this from "careful manual review" into "mechanical refactoring with a yes/no gate."
- Are there findings from the reshape's review that AREN'T drift but are real new work? Those belong in their own plan, not this one.
