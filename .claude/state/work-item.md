# Work item: Task 1 of Plan 1 (core-engine) — MIDIClient transmit path

**Source plan:** `docs/plans/2026-04-18-core-engine.md`
**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` (sub-spec 1)

## Preamble — architecture of Plan 1 (for context only)

One Swift module (`Engine`) that owns the executor, block registry, typed streams, and command queue. Blocks conform to a narrow protocol (`tick(context:) -> OutputBundle` + `apply(_ command: Command)`). The executor holds a topologically-sorted block list and runs them in order per tick, drains any queued UI commands at the top of each tick, and dispatches each command to the target block by `BlockID`. The `TickClock` fires at the step interval corresponding to the current BPM using a `DispatchSourceTimer`. Parameter changes from the UI go through a `CommandQueue` drained at the top of each tick.

Design decisions deliberately taken:

- **`CommandQueue` is thread-safe but not lock-free for Plan 1.** Lock-free re-implementation folds into Plan 10 (audio engine); API frozen so the swap is drop-in.
- **`Stream` is a fat enum**, not distinct types. Compile-time type-checked ports deferred to Plan 2+.
- **`TickContext.inputs` is a dict, allocated per-tick per-block.** Acceptable pre-audio-thread; Plan 10 revisits.

Environment note: Xcode 16 at `/Applications/Xcode.app`. `xcode-select` points at CommandLineTools, so all `xcodebuild` calls prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Task 1: Extend `MIDIClient` with a transmit path

### Scope

Plan 0 shipped MIDI client creation, enumeration, and virtual endpoints — but no `send`. This plan's `midi-out` block (Task 9) depends on being able to push MIDI to a `MIDIEndpoint`, so this task closes the hole before any block code depends on it. **Comes FIRST** so every later task can assume it exists.

Two pieces:

1. **`MIDIPacketBuilder.swift`** (new, in `Sources/MIDI/`) — a value-type builder that constructs a `MIDIPacketList` for `{note-on, note-off, cc}` payloads. Avoids the error-prone C-style `MIDIPacketListAdd` dance at every call site.
2. **`MIDIClient.send(packet:to:)`** (new method on existing `MIDIClient`) — routes a `MIDIPacketList` either via `MIDIReceived` (if the target is a virtual source this client created) or via `MIDISend` to a port (if the target is an external or virtual destination).

### Files

- Create: `Sources/MIDI/MIDIPacketBuilder.swift`
- Modify: `Sources/MIDI/MIDIClient.swift` — add `send(_:to:)` + a lazy output port
- Create: `Tests/SequencerAITests/MIDI/MIDIPacketBuilderTests.swift`
- Create: `Tests/SequencerAITests/MIDI/MIDIClientSendTests.swift`

### Tests

1. `MIDIPacketBuilderTests`: builds a note-on + note-off pair into a packet list; asserts the list's first packet's 3-byte payload matches `[0x90 | channel, pitch, velocity]`, second packet's matches `[0x80 | channel, pitch, 0]`, and the second packet's timestamp is strictly later.
2. `MIDIClientSendTests`:
   - Create a `MIDIClient` "A", a virtual destination `A.dest`. Create a separate `MIDIClient` "B", create an input port that records packets, connect the port to `A.dest`. `A.send(packet, to: A.dest)` → `B` sees the packet.
   - (Loopback via two clients avoids CoreMIDI's own-source-filter behaviour.)

### Acceptance

- `Sources/MIDI/MIDIClient.swift` has a `send` method referenced in Task 9 of the plan.
- Both test files green under `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' test`.

### Steps (TDD — follow in order)

- [ ] Write `MIDIPacketBuilderTests` (one note-on + note-off pair)
- [ ] Run it — verify it fails with "MIDIPacketBuilder not defined"
- [ ] Write `MIDIPacketBuilder` minimum to pass
- [ ] Write `MIDIClientSendTests` (2-client loopback pattern)
- [ ] Run it — verify it fails with "MIDIClient.send not defined"
- [ ] Write `MIDIClient.send` (+ a lazy output port) minimum to pass
- [ ] Run the full suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' test` — verify all green
- [ ] Commit: `feat(midi): transmit path — MIDIPacketBuilder + MIDIClient.send`

### Scope rules

You may edit the files named above plus `project.yml` (to add the new files to the Xcode target). Primary scope is `Sources/` + `Tests/`. Do NOT edit other hooks, agents, settings.json, wiki, specs, plans.

### Reporting

On DONE: commit SHA + one sentence on what passes. On BLOCKED: leave this file in place and describe what's stuck.

### On completion

After commit: `rm .claude/state/work-item.md` (the BT will route to adversarial-review next, then back here via promote-plan-task for Task 2).
