# Built: Tracks navigator selection + actions nav

Implements `2026-06-20-tracks-selection-actions-nav.md` (and the
ux-rethink-2 "Tracks (simple track view)" IA).

## Selection mode (on/off)
- A `Select` toggle sits in a small top bar of the tracks navigator
  (`TracksMatrixView.selectionTopBar`). OFF: tapping a tile opens the track
  detail (unchanged). ON ("Selecting"): tapping a tile toggles its membership
  in a transient multi-selection; selected tiles get a filled accent wash, a
  thick accent outline, and a filled checkmark replacing the mute toggle.
- A grouped/linked drum-kit collapses to one cell whose tap selects (or
  deselects) all its member tracks at once.
- Selection state is session-only runtime state on `SequencerDocumentSession`
  (`tracksSelectionMode` / `tracksSelection`) — never flushed to the document
  (Performance-Time Mutation Rule / document-truth guardrail). Turning
  selection mode off clears the selection.

## Actions nav (selection mode on AND >= 1 selected)
`TracksSelectionActionsNav` renders three actions:
- **Layer perform** -> `session.requestPhrasePerform(tab: .layers, ...)`:
  stashes the selection as `performTrackScope` and navigates to the existing
  Phrase workspace with the LAYERS tab open.
- **Same value** (the better name for the old "global perform"/global apply) ->
  `session.requestPhrasePerform(tab: .globalApply, ...)`: navigates to Phrase ->
  Global Apply with the selection pre-set in the global-apply track selector.
- **Create performance group** — rendered DISABLED with a "SOON" badge and a
  dashed outline. The durable performance-group object stays deferred per
  `perform-mode-phrase-layer-capture/feedback/2026-06-17-defer-performance-groups.md`.
  No performance-group object was built.

## Navigation plumbing
- `SequencerDocumentSession.pendingPhrasePerform` (a `{tab, trackIDs}` struct)
  is the single transient hand-off. The actions set it via
  `requestPhrasePerform`.
- `WorkspaceDetailView` observes it (`.onChange`) and switches `section` to
  `.phrase`.
- `PhraseWorkspaceView` consumes it (`consumePendingPhrasePerform`, from both
  `onAppear` and an `onChange`): opens the requested `phraseTab`, re-asserts the
  perform scope authoritatively, seeds the Global Apply selector for the
  `.globalApply` tab, then clears the pending target. `PhraseWorkspaceTab` was
  lifted from `private` to internal so the session can name it.
- No bespoke perform/layer UI lives in the tracks view — the actions navigate
  to the existing phrase surfaces.

## QA
- `VisualScenarioCommandRunner` gains `tracksSelectionMode=on|off`,
  `tracksSelect=selected|first|<uuid>`, `tracksClearSelection=true`, and
  `tracksAction=layerPerform|sameValue`, plus status keys
  `tracksSelectionMode` / `tracksSelectionCount`.
- `qa-surface-coverage.sh` rows: `02-tracks-navigator` (now asserts
  selection off), `02a-tracks-selection-actions` (selection on + 1 selected,
  shows the actions nav), `02b-tracks-layer-perform-nav` (drives Layer perform
  and asserts navigation lands on Phrase -> Layers with performScopeCount=1).
- Verified pixels in `.meta/multipass/visual-review/main/`: plain navigator
  unchanged; selection highlights the tile; the actions nav shows Layer
  perform / Same value / disabled "Create performance group (SOON)"; the
  Layer-perform action lands on Phrase -> Layers.
