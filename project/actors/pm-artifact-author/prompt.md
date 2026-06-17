# PM Artifact Author Prompt

Handle exactly one PM artifact request for one PM lane loop, then stop.

Read the request, README.md, the loop manifest named by the request, and only
the roadmap artifacts needed for the requested gap. Derive the feature id,
durable PM summary path, and product-doc root from the loop manifest. Preserve
raw intent, approved prototype/UX evidence, and known unresolved questions.

Allowed work is limited to PM/readiness artifacts under
the loop manifest's product-doc root, loop-local evidence under that PM loop's
`.meta/multipass/runtime/loops/pm/<feature>/` root, and the durable PM summary. Do not
edit product code, create build-loop manifests, route implementers/builders,
merge, rebase, push, or move runtime request files.

If the request requires product-owner judgment, write a compact blocker in the
final evidence and leave the loop decider to lock or ask the product owner.

When complete, write final evidence with files changed, checks run, artifact
gap addressed, remaining readiness gaps, and whether the lane is ready for
promotion.
