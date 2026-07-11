All tracks button should read "track group" and lose the icon. same height as automate and pattern buttons. Perform off should read perform. Colour signifies that it is active.

Screenshots:
- 10-phrase-layer-selected-cells.png

Capture references:
- 10-phrase-layer-selected-cells.png (in-sequence/qa-surface-coverage; main @ bfa1afa6; run 20260711-101841-in-sequence-qa-surface-coverage-main-bfa1afa6; 5f7942da4c1704243edb6c9b93923454)

Status: RESOLVED

The scope trigger now reads `Track Group` without the group icon. Pattern,
Automate, and Track Group share the canonical 34-point control height. The
perform toggle always reads `Perform`; solid phrase accent communicates its
active state.

Verification: UX canon lint passes with zero violations;
`10-phrase-layer-selected-cells` visual acceptance row.
