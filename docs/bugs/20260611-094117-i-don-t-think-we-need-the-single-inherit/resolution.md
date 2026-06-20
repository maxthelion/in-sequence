# Resolution

Fixed (visual + interaction), with one honest deviation noted below.

- The "SINGLE" / "INHERIT" text chips are gone from every cell. Inheritance
  is now shown as a variant of the parent: inherited cells render their
  content at a muted opacity (`StudioOpacity.inheritedContent`) with a dashed
  stroke; explicit cells are full strength. Changed:
  `Sources/UI/PhraseWorkspaceView.swift` (`PhraseGridCell`),
  `Sources/UI/PhraseCells/ScalarCellPreview.swift` (mode caption removed),
  `Sources/UI/TracksMatrixView.swift` (chip row removed from track cards).
- Normal interaction already treats the cell as single: toggling a boolean
  cell or dragging a scalar cell writes `.single(...)` — unchanged.
- Shift-click on a boolean cell now cascades: it toggles the value, writes it
  into the layer's per-track default
  (`SequencerDocumentSession.setPhraseLayerDefault`, new), and converts the
  clicked cell and every following phrase's cell to inherit it. A tooltip on
  inherited cells explains both gestures (`.help`, not surface prose).

Deviation / known limit: the model has one layer default per track, not a
chain where each phrase inherits from the previous one. So a shift-click also
moves any *earlier* phrase that was already set to inherit (they all follow
the same default). True "following descendants only" inheritance needs a new
model concept (per-phrase inheritance source) — deferred to roadmap if the
single-default behaviour proves insufficient in use. Shift-cascade is also
boolean-layer only for now; scalar cells keep drag-to-edit (a drag has no
single moment to capture a cascade value).

## Follow-up: forward-only inheritance (deviation resolved)

The "earlier phrases also move" deviation is fixed. Inheritance is now
forward-only without changing the document codec:

- An `.inheritDefault` cell resolves to the value of the nearest *preceding*
  phrase (in song order) that set an explicit value for the same layer+track,
  falling back to the layer default when none precedes it. No new per-cell
  field — `.seqai` docs load unchanged.
- New `PhraseInheritedDefaults` (Sources/Document/PhraseModel.swift) walks the
  ordered phrase list once and produces, per phrase, the value its inheriting
  cells should resolve to. `PhraseModel.resolvedValue(... inherited:)` takes an
  optional context; when `nil` it keeps the legacy layer-default behaviour, so
  the ~25 existing call sites are untouched.
- The engine compile path (Sources/Engine/SequencerSnapshotCompiler.swift)
  builds the context once per compile and threads the per-phrase slice into
  `compilePhraseBuffer`. The incremental path now recompiles the edited phrase
  *and every following phrase* (a forward edit changes later inheritors).
- Shift-cascade now anchors the clicked phrase as `.single(...)` and converts
  only *following* phrases to inherit — earlier phrases are never touched. It
  no longer writes the layer default.
- The phrase matrix display resolves with the same forward context, so cells
  show the value they will play.
