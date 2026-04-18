# Critical — Task 1: three bugs in `MIDIPacketBuilder`

**File:** `Sources/MIDI/MIDIPacketBuilder.swift`
**Severity:** Critical (fix before any other block code depends on this)

Three related issues, all in the same builder. Fix together.

## 1. `MIDIPacketListAdd` return value is unchecked → UB on buffer overflow

Lines 42–50 (`withPacketList` / `add…` loop). `MIDIPacketListAdd` returns `nil` when the buffer is exhausted. The current code assigns that into `var current` and feeds it as `curPacket` into the next call — **passing a nil pointer to `MIDIPacketListAdd` is undefined behaviour.**

**Fix:**
- Each `addNoteOn` / `addNoteOff` / `addCC` checks the pointer before storing it.
- On overflow, either throw `ClientError.packetListFull` (and make the helpers `throws`), OR surface a `Bool` return from each add… and let the caller decide.
- Recommend `throws` — it composes better through `withPacketList`.

## 2. Dead storage — `maxPackets`, `currentPacketPtr`, stored `listPtr`

Lines 22, 26–27 declare storage that is never assigned or read. The `listPtr` local in `withPacketList` (line 37) shadows the stored one. Evidence of a mid-refactor that wasn't cleaned up.

**Fix:** delete the three declarations. Document in the type's header comment that `withPacketList` is rebuild-every-call (no state carried between invocations).

## 3. 64 KiB buffer for a 128-message builder

Line 23: `bufferSize = 65536`. The header comment reasons "128 × ~14 = ~1800 bytes" but the code allocates 32× that. `MidiOut` will call this per-tick; at 16 ticks/bar × 120 BPM = ~32 ticks/sec, that's **2 MiB/sec of allocation** in the engine's hot path.

**Fix:** 
- Drop to ~2 KiB (enough for 128 short MIDI messages with headroom).
- Cap the builder's advertised capacity: if `addNoteOn` would exceed, throw or return false (ties into fix #1).
- Alternatively, have `MidiOut` reuse a single builder instance across ticks — but that requires the builder to reset between uses. If going that route, add `reset()` and document the reuse contract.

## Acceptance

- Overflow on `withPacketList` surfaces an error rather than UB.
- No dead storage in the type.
- Buffer size matches advertised capacity (2–4 KiB range).
- Tests cover each fix: (a) an overflow case asserts the error, (b) a zero-warning lint pass on dead code, (c) a sanity-check that `sizeof(packet list holder) < 4096`.
