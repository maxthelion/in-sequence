# 🔵 Minor — `MIDIClient.IncomingMIDIHandler` typealias is now used only once, and its `UnsafePointer<MIDIPacketList>` signature predates the packet API it's likely to grow into

**File:** `Sources/MIDI/MIDIClient.swift:12, 78-80`

## What's wrong

After commit 77ab1bb removed `incomingHandlers`, the typealias `IncomingMIDIHandler` is referenced only as the parameter type of `createVirtualInput(name:handler:)`. With one use site, the typealias isn't earning the indirection — a reader of `createVirtualInput`'s signature has to jump up to line 12 to discover it's a closure type.

Secondary: the typealias uses the legacy `MIDIPacketList` signature:

```swift
typealias IncomingMIDIHandler = (UnsafePointer<MIDIPacketList>) -> Void
```

Modern CoreMIDI prefers `MIDIEventList` with `MIDIReceiveBlock`, which supports MIDI 2.0 (UMP). The north-star spec (`docs/specs/2026-04-18-north-star-design.md:19`) explicitly plans MIDI 2.0 support: _"MIDI; MIDI 2.0 where the device supports it"_. Using `MIDIDestinationCreateWithBlock` + `MIDIPacketList` caps this API at MIDI 1.0 forever unless rewritten.

## What would be right

Option A: inline the closure type, remove the typealias.

```swift
func createVirtualInput(
    name: String,
    handler: @escaping (UnsafePointer<MIDIPacketList>) -> Void
) throws -> MIDIEndpoint { ... }
```

Option B: migrate to the event-list API now, before the typealias proliferates:

```swift
typealias IncomingMIDIEventHandler = (UnsafePointer<MIDIEventList>) -> Void
// ... and use MIDIDestinationCreateWithProtocol to specify MIDI 1.0 or 2.0 protocol.
```

The wiki page `midi-layer.md` already says _"MIDI 2.0 where the device supports it (similar to what the [[phat]] project already uses via its MIDIManager)"_ — worth migrating before the API has consumers.

## Why it matters

Neither item is a bug today. But the typealias-with-one-site is the archetype of structural cost that accumulates — as soon as a second user appears, the indirection is already there and gets preserved; as soon as MIDI 2.0 is needed, there's a parallel-types refactor cost. Cheap to fix now, expensive if left for plan 1 or 2.
