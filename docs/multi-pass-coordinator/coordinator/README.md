# Coordinator Memory

This directory is durable memory for the project-local multi-pass loop.

It is intentionally markdown rather than a deterministic state model. Observer
actors update these files. The coordinator/decider reads them and decides what
to schedule next.

## Shape

- `current-work/`: one checklist per active work item, lane, slice, or probe.
- `holistic-status.md`: zoomed-out product coherence and pyramid status.
- `decision-log.md`: short notes explaining why work was scheduled.
- `templates/`: copyable markdown shapes for new work items and observer
  outputs.

## Rule

The observers describe state and tension. The coordinator chooses action.

