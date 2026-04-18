---
title: "MIDI Layer"
category: "architecture"
tags: [midi, coremidi, sources, destinations, virtual-endpoints, session]
summary: The MIDI module — MIDIEndpoint value type, MIDIClient CoreMIDI wrapper, MIDISession app-level composition — including the CoreMIDI vs user-facing naming decision.
last-modified-by: user
---

## Module shape

Three files in `Sources/MIDI/`, each with one responsibility:

- `MIDIEndpoint.swift` — a value type wrapping a CoreMIDI endpoint ref + role + display name
- `MIDIClient.swift` — a class wrapping a CoreMIDI client ref; owns virtual endpoints it created
- `MIDISession.swift` — an `@Observable` singleton composing a `MIDIClient` plus the two app-level virtual endpoints

These are used by `SequencerAIApp` (to boot the session at launch) and `PreferencesView.MIDIPreferences` (to display what's connected). No other subsystem reaches into the MIDI module in the current scaffold.

## The naming decision: CoreMIDI terms, not app-perspective

`MIDIClient` exposes endpoints using CoreMIDI's own terminology:

```swift
var sources: [MIDIEndpoint]       // MIDIGetNumberOfSources / MIDIGetSource
var destinations: [MIDIEndpoint]  // MIDIGetNumberOfDestinations / MIDIGetDestination
```

And:

```swift
enum MIDIEndpoint.Role {
    case source        // a MIDI producer (enumerated by MIDIGetSource)
    case destination   // a MIDI consumer (enumerated by MIDIGetDestination)
}
```

This is **not** the user's perspective. From a user's point of view, a MIDI keyboard (a system source) is an *input* to the app, and a hardware synth (a system destination) is an *output*. But the app-perspective naming caused real confusion during implementation: a virtual source this app creates (so other apps can read from us) is an *output* from our point of view, but CoreMIDI files it under sources — so "my output" appeared in "inputs." The fix was to use CoreMIDI's terminology at the API layer and let the UI translate.

### Where user-perspective labels live

In `PreferencesView`, the tab displays **Inputs** and **Outputs** as user-facing section labels, mapping:

- "Inputs" ↔ `MIDISession.shared.sources` (everything the app can read from: hardware keyboards, other apps' virtual sources, and the app's own virtual sources that other apps can see)
- "Outputs" ↔ `MIDISession.shared.destinations` (everything the app can write to: hardware synths, other apps' virtual destinations)

This mapping is only at the UI boundary; the data model stays CoreMIDI-correct.

### Method names are still app-perspective

`createVirtualOutput(name:)` and `createVirtualInput(name:handler:)` keep app-perspective names because users of the API are app-centric ("I want a MIDI output for this app to send through"). The returned `MIDIEndpoint`'s `.role` follows CoreMIDI, so a `createVirtualOutput` returns a `.source`. Doc comments explain the inversion at the call site. Caller-facing cognitive load is unavoidable given CoreMIDI's own taxonomy.

History: initial implementation used `inputEndpoints` / `outputEndpoints` and `Direction.input` / `.output`. Renamed in commit `d33c72f`. See [[code-review-checklist]] §5 on naming.

## `MIDIEndpoint`

Value type. Failable init (returns nil if the ref is 0). Display name defaults to `"Unknown MIDI Endpoint"` if `MIDIObjectGetStringProperty` fails — this fallback exists for UI robustness but means any test asserting `displayName.isEmpty == false` is tautological; tests should assert against the specific expected name when possible.

```swift
struct MIDIEndpoint: Identifiable, Hashable {
    enum Role { case source, destination }
    let id: MIDIUniqueID
    let ref: MIDIEndpointRef
    let displayName: String
    let role: Role
}
```

## `MIDIClient`

Class. Owns a `MIDIClientRef` and arrays of `MIDIEndpointRef` for virtual endpoints it created. Disposes everything in `deinit`.

Responsibilities:

- Create a CoreMIDI client on init via `MIDIClientCreateWithBlock` (the block will eventually handle device add/remove notifications)
- Enumerate system sources and destinations on demand
- Create virtual sources (via `MIDISourceCreate`) and virtual destinations (via `MIDIDestinationCreateWithBlock`)

It does **not** own the session-level concept of "the app's own MIDI endpoints" — that's `MIDISession`'s job.

### Threading

The notification block passed to `MIDIClientCreateWithBlock` runs on a CoreMIDI-internal thread. Currently the block is a no-op; when later plans add device-hot-plug handling, mutations from that block must marshal to match main-thread reads. A comment in `init` flags this.

No internal synchronization today; `MIDIClient` is expected to be used from the main thread only. This is acceptable while the notification block is empty.

### Resource ownership

Every created virtual endpoint ref is kept in an array. `deinit` disposes all of them, then disposes the client. This is tested indirectly — the full test suite creating many `MIDIClient` instances across tests runs without warning.

## `MIDISession`

The app-level composition:

```swift
@Observable
final class MIDISession {
    static let shared: MIDISession
    let client: MIDIClient?        // nil if CoreMIDI client creation failed
    let clientError: Error?
    private(set) var appInput: MIDIEndpoint?
    private(set) var appOutput: MIDIEndpoint?

    var sources: [MIDIEndpoint] { client?.sources ?? [] }
    var destinations: [MIDIEndpoint] { client?.destinations ?? [] }
}
```

Singleton because there's exactly one MIDI system per process. Touched in `SequencerAIApp.init` so the virtual endpoints register at app launch rather than lazily on first UI access.

### Virtual endpoints

On init, the session attempts to create:

- `SequencerAI Out` — a virtual source; other apps see it as a MIDI input they can subscribe to. The eventual pipeline-engine writes MIDI here when a track's sink is `midi-out` targeted at the app's own virtual output.
- `SequencerAI In` — a virtual destination; other apps see it as a MIDI output they can send to. The handler currently no-ops; a later plan wires it into the engine for MIDI-input-driven features (chord-context live feed, manual-pitch capture).

If either creation fails the session logs via `NSLog` and continues; the UI's "Virtual (this app)" section reports what's available.

### Observability

`@Observable` (Swift Observation framework, macOS 14+). The `sources`/`destinations` computed properties return fresh enumerations on every access but are **not** backed by tracked stored state — so SwiftUI views watching these won't re-render when hardware hot-plugs. A `refreshTick` in `PreferencesView.MIDIPreferences` works around this until the notification block subscribes to `kMIDIMsgObjectAdded` / `kMIDIMsgObjectRemoved` and mutates tracked state. A TODO comment in `MIDIPreferences` points at the fix.

## Testing

`Tests/SequencerAITests/MIDIClientTests.swift` — 6 tests:

- Client init without error
- Sources / destinations enumeration doesn't crash (may be empty on CI)
- Non-fallback display names where present
- Virtual output creation + display-name preservation
- Virtual input creation + display-name preservation
- Created virtual output appears in `sources` (round-trip via CoreMIDI enumeration)

Tests hit real CoreMIDI — no mocking — which is the right call for a thin OS-API wrapper: mocked tests would pass even if the real API had changed behavior.

## Related pages

- [[project-layout]] — where `MIDI/` sits in the module graph
- [[build-system]] — entitlements that affect MIDI permissions
- [[code-review-checklist]] — §1 (contracts), §6 (resource ownership), §9 (Swift specifics)
