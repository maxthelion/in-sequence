# Resolution

Fixed in `Sources/UI/PhraseWorkspaceView.swift` (`PhraseMatrixPhraseCell`).

- The bars/repeat editable steppers are now always visible — no
  collapsed/expanded toggle, no chevron (ux-canon rule 4: edit in place).
- The grey summary line ("4 bars | 1x repeat") is gone; it duplicated the
  values shown in the steppers right below it (rule 1 / rule 10).
- The SEL badge is gone; selection is already shown by the cell's fill and
  stroke.
- The "Loop off" toggle is gone; it duplicated the transport bar's Song/Free
  mode control. Play and Queue badges remain — they are the phrase's own
  state.

Supporting changes:

- `Sources/UI/PhraseButtonControlPresentation.swift` — dropped the now-unused
  `PhraseButtonControlsState` (open/close tracking), `collapsedSummary`, and
  `loopStatusLabel`; the accessibility label keeps bars/repeat/loop state.
- `phraseControlsOpenIndex` visual commands still work: they select the
  requested phrase (the controls are always visible, so there is nothing to
  open). The QA capture row `10-phrase-controls-open` waits on a runner-owned
  status key, so `scripts/visual-scenarios/qa-surface-coverage.sh` needed no
  change.

Deliberately not done: `loopEnabled` stays in the model and engine (documents
that already loop keep looping, and the cell still tints amber for it); only
the redundant per-phrase toggle was removed. If per-phrase loop authoring is
wanted again it belongs in the transport phrase picker, not in every cell.
