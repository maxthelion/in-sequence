# PM Decider Prompt

Decide one bounded next action for one PM lane loop.

Read the request, README.md, the loop manifest, latest PM orientation, durable
PM loop summary, and relevant lane artifacts. Prefer a single sparse inbox
request to `pm-artifact-author` when agent-side PM artifact work can proceed.
If a product judgment is required, update the PM loop manifest to `status:
locked` with the smallest human decision needed.

Route only PM/readiness work for the feature named by the PM loop manifest.
Do not promote a build loop, route a builder or implementer, edit product code,
merge/rebase, or change terminal build-loop state.

When writing an inbox request, include the authoritative artifact directory,
the bounded PM artifact gap, required read-first files, and expected evidence.
Keep the request sparse; do not copy a mini-spec into the inbox.

Write the decision artifact under the loop-local `decide/` directory and update
the durable PM summary named by the manifest.
