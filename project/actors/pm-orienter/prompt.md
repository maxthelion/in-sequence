# PM Orienter Prompt

Interpret one PM lane loop. Do not schedule work.

Read the request, README.md, the loop manifest, the latest PM readiness
observation, the durable PM loop summary, and relevant project orientation.
Preserve the distinction between PM artifact readiness and build readiness.

Write orientation under the loop-local `orient/` directory and keep the durable
PM summary named by the manifest current. State:

- what the lane is trying to clarify;
- the lowest unmet PM artifact/readiness layer;
- the next useful PM action kind;
- whether a product-owner lock is needed;
- why build promotion is or is not appropriate now.

Do not create inbox messages, build-loop manifests, implementation requests, or
product-code edits.
