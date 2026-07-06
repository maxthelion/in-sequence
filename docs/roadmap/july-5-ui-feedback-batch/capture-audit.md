# July 5 UI Feedback Capture Audit

Status: complete against latest captures
Audited: 2026-07-06
Capture source: `.meta/multipass/visual-review/july-5-ui-feedback-batch/`
R2 manifest: `.meta/multipass/visual-review/manifests/july-5-ui-feedback-batch-latest.json`

The latest gallery has 72 PNG captures. The full suite completed with no skipped
rows, then `29c` and `29f` were recaptured after the final kit mixer/capture
polish, and the now-duplicate retired `10` automation-tool row was pruned. The
stable R2 manifest has 72 rows.

Summary across 19 reports: 19 pass, 0 partial, 0 fail, 0 not proven.

## One-by-one Status

- `[x] PASS` `20260705-102035-all-tracks-should-have-a-border-that-is`
  - Capture: `02-tracks-navigator.png`
  - Track cards use colour-matched borders and the old unexplained top-right
    glyph is gone. The implementation also uses the shared right-click
    selection probe for track cells.

- `[x] PASS` `20260705-102540-when-a-track-is-selected-allow-copy-and`
  - Capture: `02a-tracks-selection-actions.png`
  - Selected-track actions now show `Copy`, `Paste`, `By Track`, `By Value`,
    and `Delete` in the action bar.

- `[x] PASS` `20260705-102958-right-click-a-cell-here-to-show-more-men`
  - Capture: `02b-tracks-layer-perform-nav.png`
  - The old `VALUE` tool pill is gone from the phrase layer bar. Cell context
    menus provide Select, Add to Selection, Copy Value, Paste Value when a
    layer-compatible clipboard exists, and Automation for a single selection.

- `[x] PASS` `20260705-103104-the-text-should-be-bigger-maybe-centrall`
  - Capture: `02c-create-track-modal.png`
  - Create-track option labels are larger and centered.

- `[x] PASS` `20260705-150256-let-s-leave-out-the-routing-part-it-shou`
  - Capture: `02d-add-drum-group-modal.png`
  - Routing is gone, empty creation is possible, `Add part` is visible, and the
    old Sounds/Patterns section title/rule chrome is gone.

- `[x] PASS` `20260705-150325-get-rid-of-grey-subtext-and-line-after-h`
  - Capture: `02e-add-slice-track-loop-picker.png`
  - Grey explanatory subtext and the decorative title rule are gone.

- `[x] PASS` `20260705-193532-let-s-make-the-aus-one-colour-border-the`
  - Capture: `02f-create-track-sound-step.png`
  - AU choices, Sampler, and Leave Blank use distinct border colours, and the
    decorative track-heading rule is gone.

- `[x] PASS` `20260705-193605-the-send-channels-should-be-the-same-hei`
  - Capture: `04-mixer.png`
  - Send returns match the height and visual weight of the main mixer strips.

- `[x] PASS` `20260705-193840-the-big-number-in-each-cell-should-be-ce`
  - Capture: `05-scenes-browse.png`
  - Scene cards use simple A/B slot pills, slot-coloured borders, and centered
    large scene numbers without duplicated A:1/B:2 pills.

- `[x] PASS` `20260705-193958-we-don-t-need-scene-name-at-the-top-perh`
  - Capture: `05a-scenes-edit-empty.png`
  - The scene editor shows just the scene number; the old scene name header and
    blue underline are gone.

- `[x] PASS` `20260705-194029-get-rid-of-the-2-8-text-above-macros`
  - Capture: `05b-scenes-edit-content.png`
  - The old `2 / 8` macro count is gone.

- `[x] PASS` `20260705-194506-we-don-t-need-this-with-the-new-slot-vie`
  - Capture: `06b-phrase-scenes-perform-slots.png`
  - The old `06a-phrase-scene-select.png` row is retired; the slot view is the
    captured surface.

- `[x] PASS` `20260705-194642-the-whole-of-the-top-of-each-slot-should`
  - Captures: `06-phrase-scenes-perform.png`,
    `06b-phrase-scenes-perform-slots.png`
  - Each phrase-scene slot uses a large `A:1` / `B:2` top label with no
    separate `Slot A` title or scene-name duplication.

- `[x] PASS` `20260705-194854-this-would-be-a-more-useful-capture-if-i`
  - Capture: `20-track-fill-preview-active.png`
  - The capture now shows the step sequencer with Fill Preview enabled.

- `[x] PASS` `20260705-195208-the-empty-fx-well-should-be-black-not-gr`
  - Capture: `29a-drum-kit-fx-tab.png`
  - The drum-kit FX well is captured and reads as dark/black empty space rather
    than a grey panel.

- `[x] PASS` `20260705-195311-get-rid-of-kit-wide-macro-sweeps-text-ma`
  - Capture: `29b-drum-kit-macros-tab.png`
  - The kit-wide macro sweeps copy is gone, and macro rotaries render with the
    same no-grey-panel treatment as the other rotary surfaces.

- `[x] PASS` `20260705-195340-this-is-now-inconsistent-with-other-trac`
  - Capture: `29c-drum-kit-mixer-tab.png`
  - The kit mixer tab now includes the A/B/A+B scene membership selector,
    applied across kit member tracks, matching normal track mixer grammar.

- `[x] PASS` `20260705-195724-this-is-quite-messy-get-rid-of-the-captu`
  - Capture: `29f-drum-kit-capture-save-slot.png`
  - The Capture History title is gone, save is in the top control row, the
    bottom capture area is bordered, per-part triggered steps are compressed,
    and the save target uses pattern slot buttons.

- `[x] PASS` `20260705-195817-this-needs-to-be-less-grey-and-low-contr`
  - Capture: `35-drum-kit-matrix-velocity-layer.png`
  - Drum-kit matrix rows no longer add a grey row fill; they sit on the kit well
    with neutral outlines and stronger active value colour.
