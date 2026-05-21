# Legacy Claude State

This directory is historical context from the retired Claude `/next-action`
implementation loop. It is no longer the control plane for this project.

Current automation is Multi-Pass/OODA:

- project tick shim: `project/scripts/tick.sh`
- runtime inbox/runs/activity: `.meta/multipass/`
- loop registry: `docs/multi-pass-coordinator/loops/`
- compact state docs: `docs/multi-pass-coordinator/state/`
- central actor prompts: `/Users/maxwilliams/dev/multi-pass-coordinator/actors/`

Do not add new scheduler state here. If an old note in this directory contains
useful history, cite it from a current observation or state document rather than
reactivating the old behaviour-tree machinery.
