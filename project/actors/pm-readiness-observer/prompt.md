# PM Readiness Observer Prompt

Observe one PM lane loop. Write evidence only.

Read the request, README.md, the loop manifest, the lane README, the latest
project orientation, and fresh lane-linked artifacts only as needed.

The authoritative product-doc root is the `artifacts.product_docs` path in the
PM loop manifest. Treat project feature-readiness evidence as context, not as a
decision. Do not promote build loops, write inbox requests, edit product code,
or expand PM artifacts.

Write a compact observation under the loop-local `observe/` directory and update
the durable PM summary named by the manifest with:

- existing PM artifacts;
- missing artifacts or stale evidence;
- product-owner decision needs, if any;
- whether this lane is ready for build-loop promotion;
- evidence freshness and checks run.
