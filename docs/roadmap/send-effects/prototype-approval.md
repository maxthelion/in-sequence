---
status: approved
approved: 2026-05-03
approved_by: user
approval_scope: mixer-lane
prototype: prototypes/01-mixer-send-knobs.html
supporting_prototypes:
  - prototypes/02-send-bus-insert-chain.html
  - prototypes/03-signal-flow-overview.html
---

# Prototype Approval

The Send Effects prototype set is approved as part of the mixer-lane direction.

## Approval Notes

- Use the per-track send knob treatment from prototype 01.
- Use the send bus insert-chain treatment from prototype 02.
- Treat prototype 03 as a planning/architecture artifact, not a production screen.
- Apply the approved send decisions in `decisions.md`.
- Send A and Send B inserts are global in v1.
- Send returns connect after master effects at `finalOutputMixer`.
- Muted tracks do not contribute dry or wet send signal in v1.
- Do not ask for a separate visual prototype review unless later feedback invalidates the lane direction.
