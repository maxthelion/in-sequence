# Important — Task 1: input validation + test-coverage gaps

**Files:**
- `Sources/MIDI/MIDIPacketBuilder.swift`
- `Sources/MIDI/MIDIClient.swift`
- `Tests/SequencerAITests/MIDI/MIDIClientSendTests.swift`
- `Tests/SequencerAITests/MIDI/MIDIPacketBuilderTests.swift`

**Severity:** Important (fix before Plan 1 tags — these are correctness and coverage gaps, not UB).

Five findings from the adversarial review of `f5a98f3`.

## 4. Silent bitmask truncation of channel / pitch / velocity

`MIDIPacketBuilder.swift:65,76,88`. `channel & 0x0F`, `pitch & 0x7F`, `velocity & 0x7F` silently truncate. `addNoteOn(channel: 20, …)` produces channel 4 with no warning.

**Decide the project-wide style now — it'll recur in every block that takes a MIDI parameter:**

- **Option A:** typed wrappers (`struct MIDIChannel { init?(_ raw: UInt8) }`, `MIDIPitch`, `MIDIVelocity`). Compile-time correct; slightly heavier ergonomics.
- **Option B:** `precondition(channel < 16)` — programmer-error, crashes early.
- **Option C:** `throws` on invalid input.

Recommend A for values that cross module boundaries (channel, pitch), B for internal invariants. Apply consistently in Task 8+ as well.

## 5. Test skips the `MIDIReceived` branch of `send(_:to:)`

`MIDIClient.swift:107-112` has two branches — `MIDIReceived` (owned virtual source) vs `MIDISend` (output-port-to-destination). `MIDIClientSendTests` only exercises the second. The first is currently untested — an implementation that always called `MIDIReceived(0, …)` would pass every existing test.

**Fix:** add a test that creates a virtual source on client A, a listening input port on client B connected to that source, sends via A, asserts B observes.

## 6. Test departs from plan's 2-client loopback wiring

Plan Task 1: *"client A owns destination, client B creates an input port that records packets, connect the port to A.dest."* Actual test puts the recording handler on client A's own `createVirtualInput` callback; client B only sends. Result: 1-direction test, not a loopback — can't catch a regression in CoreMIDI's own-source filter.

**Fix:** restructure `test_send_loopback_roundtrip` to wire the recording port on client B, not A. Keep the scenario but swap the roles.

## 7. `send` has no contract for empty lists or disposed endpoints

`MIDIClient.swift:106-121` — public method, undocumented failure modes:

- Empty `packetList` (`numPackets == 0`) is a silent no-op today.
- `endpoint.ref == 0` or post-disposal: undefined.
- No return value indicating success.

**Fix:** document the contract in the doc comment. If errors can't leak, say so. If they can, make the method `throws` or return an `OSStatus`.

## 8. Packet-list test hard-codes a layout offset

`MIDIPacketBuilderTests.swift:20-22,49-51` uses `UnsafeRawPointer(listPtr).advanced(by: MemoryLayout<UInt32>.size)` — assumes the first packet starts at offset 4. `MIDIPacketList`'s actual layout depends on CoreMIDI's packing attributes, which have historically varied.

**Fix:** use `MemoryLayout<MIDIPacketList>.offset(of: \.packet)!` for the first packet and `MIDIPacketNext(&packet)` for iteration. The test passes today by coincidence; a non-zero timestamp on a non-packed platform could misread.

## Acceptance

- All 4 new fix tests green.
- Validation style decision documented in the project (wiki/pages/code-review-checklist.md §1 "Contracts" or similar).
- Both branches of `send` covered.
