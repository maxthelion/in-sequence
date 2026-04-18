# Minor — Task 1: four style/doc/thread-safety nits

**Files:**
- `Sources/MIDI/MIDIPacketBuilder.swift`
- `Sources/MIDI/MIDIClient.swift`
- `Sources/MIDI/MIDISession.swift` (adjacent — noted for completeness but not in Task 1 scope)

**Severity:** Minor

Four findings. Address opportunistically or roll into the next MIDI-touching task.

## 9. `withPacketList` is `mutating` but shouldn't need to be

`MIDIPacketBuilder.swift:35`. Only mutating because `buffer.withUnsafeMutableBytes` requires mutable access. Builder's logical state is unchanged between calls.

**Fix:** move the buffer into a `ManagedBuffer` or a small reference-wrapper, so `withPacketList` is non-mutating and the type is usable against a `let` binding. Swift idiom for `with…` closures is non-mutating.

## 10. Doc-comment example bypasses the new public API

`MIDIPacketBuilder.swift:13-15` shows usage via `MIDISend(outputPort, destination, ptr)` directly — bypassing `MIDIClient.send(_:to:)` that this plan just added. Misleads future readers about the supported path.

**Fix:** change the example to `client.send(ptr, to: endpoint)`.

## 11. `lazyOutputPort` is not thread-safe

`MIDIClient.swift:126-133`. If `send` runs from two threads concurrently before `outputPortRef` is set, `MIDIOutputPortCreate` gets called twice and the first port leaks.

**Why minor for Plan 1:** CommandQueue is single-producer and `send` runs on the engine tick, so no contention today. But the type's threading contract is unspoken, and Plan 10's audio-thread migration will hit it.

**Fix:** guard with an `os_unfair_lock` or make the port eager in `MIDIClient.init`. Add a doc-comment on `send` stating the threading model.

## 12. Unrelated: `MIDISession.shared.createVirtualInput` has a `TODO(phase 2)` dropping incoming MIDI

`Sources/MIDI/MIDISession.swift:27-29`. Not in Task 1's scope but noted by the adversarial reviewer. The singleton silently discards incoming MIDI.

**Fix (defer):** log-on-drop at minimum. Track as a candidate; fold into whichever future task exercises `midi-in` (Plan 2+).

## Acceptance

- 9–11 addressed (11 gets a doc-comment even if the implementation waits for Plan 10).
- 12 → logged and moved to `.claude/state/insights/` or to a future candidate list, not left silent.
