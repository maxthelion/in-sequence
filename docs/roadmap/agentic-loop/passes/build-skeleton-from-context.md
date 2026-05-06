---
id: build-skeleton-from-context
mode: build-skeleton
status: draft
created: 2026-05-06T13:23:36.000Z
objective: Build App-Shaped Skeleton From Context
max_parallel: 1
requires_context_pack: true
---

# Build App-Shaped Skeleton From Context

## Objective

The loop has context but no app-shaped skeleton pass yet.

## Required Inputs

- `docs/roadmap/context-pack.md`
- current lane files under `docs/roadmap/lanes/`
- current probe results under `docs/roadmap/probe-results/`
- current wiki pages linked from the context pack

## Expected Outputs

- whole-app synthesis or skeleton notes;
- links to evidence;
- follow-up work that agents can handle;
- a tiny user-attention item only if judgment is genuinely needed.

## Review Lenses Required

- UX/IA
- architecture
- testing

## Stop Conditions

- resource gate fails;
- context pack is missing;
- output would be lane-local without explaining whole-app fit.
