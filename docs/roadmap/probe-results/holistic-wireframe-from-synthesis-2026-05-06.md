---
status: complete
created: 2026-05-06T17:28:11+01:00
source_pass: docs/roadmap/agentic-loop/passes/build-holistic-wireframe-from-synthesis.md
visual-capture-status: valid
host: local-html-prototype
---

# Holistic Wireframe From Synthesis

## Result

Built a probe-scoped **Happy Accident Workbench** interactive skeleton from the
current product-shape synthesis.

Artifacts:

- Prototype host: `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/index.html`
- Fixture/model: `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.js`
- Focused tests: `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.test.js`
- UI map: `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/ui-map.json`
- Screenshot: `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/screenshot.png`

The wireframe is intentionally disposable. It uses a local HTML/JS fixture to
show product shape and validation evidence without changing Swift document
schema, playback, or audio graph contracts.

## Scenario Fixture Coverage

The fixture seeds:

- drum/group, melodic generator, audio input/loop, and bass clip tracks;
- one active phrase and one queued phrase;
- one captured generated clip in history, preserving the generator recipe ID;
- one shared audio buffer with loop range, slice cues, and multiple users;
- one transient performance override across the selected track set;
- one mixer route through Drum Bus plus Delay Return and Reverb Return;
- Scene A/B state with a live crossfader override.

Ownership labels are explicit:

| Surface Object | Owner Label |
|---|---|
| Phrase rows, pattern slots, captured clip history | document |
| Selected track set, transient overrides, live crossfader | runtime session |
| Shared audio buffer, loop range, slice cues | runtime audio buffer |
| Drum bus, returns, post-blend master | audio graph |
| Counter/acknowledgement interactions | probe-only visual state |

## UX/IA Reading

The first viewport shows the intended whole-app journey in one surface:

- what is sounding now: transport, phrase step, selected tracks, source states,
  and consequence rail;
- what was generated or captured: clip history beside the selected source slot;
- what can be captured next: **Capture Generated Clip** and **Capture Loop To
  Shared Buffer** actions;
- what is transient: live override badges, Scene A/B override, consequence rail,
  and visible **Keep** / **Discard** controls.

This keeps audio capture as the strongest first-viewport anchor, while phrase,
scene, performance override, and mixer routing are visible as consequences of
the same musical state instead of separate lane panels.

## Validation

Focused model tests:

```text
node --test docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.test.js
```

Result: 4 tests passed.

Host/render validation:

```text
python3 -m http.server 8765 --bind 127.0.0.1
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --disable-gpu --window-size=1440,960 --screenshot=docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/screenshot.png http://127.0.0.1:8765/
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --disable-gpu --virtual-time-budget=1000 --dump-dom http://127.0.0.1:8765/
```

Result: screenshot is a 1440 x 960 PNG and DOM evidence includes the intended
workbench labels, capture actions, Keep/Discard controls, and routing summary.

`visual-capture-status: valid`

## Review Lenses For Next Loop Pass

Run agent-side lens reviews before asking the user to judge the shape:

| Lens | Agent-Actionable Review Output |
|---|---|
| UX/IA | `docs/roadmap/agentic-loop/reviews/holistic-wireframe-from-synthesis/ux-ia.md` |
| Architecture | `docs/roadmap/agentic-loop/reviews/holistic-wireframe-from-synthesis/architecture.md` |
| Testing | `docs/roadmap/agentic-loop/reviews/holistic-wireframe-from-synthesis/testing.md` |

Review should decide whether the wireframe is strong enough to become the next
source-of-truth shape for production cherry-picks. Do not ask the user to inspect
raw lane branches first.

## Follow-Up Work

| Priority | Work | Output |
|---|---|---|
| P0 | Review this wireframe through UX/IA, architecture, and testing lenses. | Three review files under `docs/roadmap/agentic-loop/reviews/holistic-wireframe-from-synthesis/`. |
| P0 | Convert accepted wireframe decisions into inferred defaults, especially capture/buffer ownership, Keep/Discard semantics, and return-style sends. | `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`. |
| P1 | Prepare cherry-pick candidates for pure model/test artifacts only after reviews pass. | Candidate list separating production-safe model/tests from probe UI state. |
| P1 | Retry failed feedback lanes only after disk preflight passes and with `max_parallel: 1`. | Follow-up pass with visual gates. |

No immediate user attention is required. The next useful user question, after
agent reviews pass, is a single product judgment: whether this integrated
workbench should become the source-of-truth shape for the next build round.
