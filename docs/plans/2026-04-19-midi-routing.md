# MIDI Routing Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a project-level MIDI routing engine that sits between track note output and destinations — AUM-style matrix. Lets a track's notes fan out to (a) the track's own `Voicing` destination AND (b) any number of additional routes: other tracks' inputs (for chord generators feeding consumers), auxiliary MIDI endpoints, or chord-context broadcast. A track with `Voicing.default = .none` relies entirely on the routing engine; a track with a set destination plus routes fans out to both. Verified end-to-end by: a chord-generator track wired to feed two consumer tracks propagates chord-context updates on each tick; a track's MIDI duplicated to two MIDI endpoints arrives on both.

**Architecture:** Routes live on the project (`document.routes: [Route]`). Each route is `{ source, filter, destination }`. The `MIDIRouter` (app-lifetime singleton, or owned by `EngineController`) subscribes to every track's per-tick note-output AND to chord-context broadcasts, then — for each matching route — dispatches the event to the route's destination. Route destinations include `Voicing`'s existing types (`.midi`, `.auInstrument`, `.internalSampler`, `.none`) plus two new options: `.trackInput(TrackID)` and `.chordContext(tag: String?)`. The router runs on the engine thread; it reads an immutable snapshot of the routes list at tick time (copy-on-write). UI edits to the routes list re-snapshot on the next tick. This plan does NOT implement internal-sampler audio — that's a later audio plan; routing TO an internal-sampler destination still fires through the router correctly, the sampler just needs to be wired.

**Tech Stack:** Swift 5.9+, Foundation, XCTest. Engine uses the existing `CommandQueue` for UI → engine command delivery. No new package dependencies.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — §"Pipeline layer" (sinks include `voice-route`, `chord-context`, `midi-out`), §"Components inventory" (`voice-route` drum sink), §"Chord as a first-class pipeline" (chord-gen → chord-context broadcast).

**Environment note:** Xcode 16 at `/Applications/Xcode.app`. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Status:** <STATUS_PREFIX> <COMPLETED_MARKER> TBD. Tag `v0.0.6-midi-routing` at TBD.

**Depends on:** `2026-04-19-track-destinations.md` — needs `Destination`, `Voicing`, `AudioInstrumentHost`. Executes after that plan lands.

**Deliberately deferred:**

- **Routing view UI** — this plan ships the engine + data types + a minimal "Routes" list in the inspector. The full AUM-style matrix view is a separate UI plan.
- **Internal-sampler audio** — routes TO `.internalSampler` destinations fire the event correctly; the sampler AU itself ships with a later audio plan.
- **Filter predicates beyond track-type / tag match** — per-note-range, per-velocity-range, per-channel filters are future extensions. MVP filter surface: `.all`, `.voiceTag(tag)`, `.noteRange(lo, hi)`.
- **Latency / jitter analysis** — the router is tick-aligned; sub-tick scheduling is out of scope. Audio-side will introduce sample-accurate timing.

---

## File Structure

```
Sources/
  Document/
    Route.swift                        # NEW — Route value type + RouteDestination + RouteFilter
    SeqAIDocumentModel.swift           # MODIFIED — document.routes: [Route]
  Engine/
    MIDIRouter.swift                   # NEW — tick-synchronous fan-out
    EngineController.swift             # MODIFIED — hold router; snapshot routes per tick;
                                       #   broadcast track-note-output + chord-context events through router
    Blocks/
      ChordContextSink.swift           # NEW — block that publishes chord-context to router
  UI/
    RoutesListView.swift               # NEW — compact list of project routes (add/remove/edit)
    RouteEditorSheet.swift             # NEW — source/destination pickers
    DetailView.swift                   # MODIFIED — surface per-track "Routes out" count in track header
Tests/
  SequencerAITests/
    Document/
      RouteTests.swift
    Engine/
      MIDIRouterTests.swift
      ChordContextRoutingTests.swift
      TrackFanOutTests.swift
```

---

## Task 1: `Route` value type

**Scope:** Pure data. No routing logic yet.

**Files:**
- Create: `Sources/Document/Route.swift`
- Create: `Tests/SequencerAITests/Document/RouteTests.swift`

**Types:**

```swift
public struct Route: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var source: RouteSource
    public var filter: RouteFilter
    public var destination: RouteDestination
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        source: RouteSource,
        filter: RouteFilter = .all,
        destination: RouteDestination,
        enabled: Bool = true
    )
}

public enum RouteSource: Codable, Equatable, Sendable {
    case track(TrackID)                        // track's note output
    case chordGenerator(TrackID)               // track's chord-context output (a chord-gen track)
}

public enum RouteFilter: Codable, Equatable, Sendable {
    case all
    case voiceTag(VoiceTag)                    // drum-like: only events tagged "kick" etc.
    case noteRange(lo: UInt8, hi: UInt8)       // pitch filter
}

public enum RouteDestination: Codable, Equatable, Sendable {
    case voicing(TrackID)                      // deliver to a track's Voicing default tag
    case trackInput(TrackID, tag: VoiceTag?)   // deliver to a specific input tag on a track
    case midi(port: MIDIEndpointName, channel: UInt8, noteOffset: Int)
    case chordContext(broadcastTag: String?)   // fan to the project-wide chord-context bus; optional named lane
}
```

**Tests:**

1. Round-trip Codable for each variant combination.
2. Equality: two routes with the same fields are equal; differing `enabled` makes them unequal.
3. A route with `source: .chordGenerator(...)` and `destination: .chordContext(...)` round-trips cleanly (the common chord-gen setup).
4. Identity: `route.id` survives round-trip.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): Route value type + RouteSource/Filter/Destination`

---

## Task 2: `document.routes: [Route]`

**Scope:** Add the list to the document model. Legacy decoder defaults to empty.

**Files:**
- Modify: `Sources/Document/SeqAIDocumentModel.swift`
- Modify: `Tests/SequencerAITests/SeqAIDocumentTests.swift`

**Changes:**

- `var routes: [Route] = []` on `SeqAIDocumentModel`
- Codable: write and read the field; decoder defaults to `[]` when absent
- Convenience: `document.routes(sourcedFrom: TrackID) -> [Route]` filter helper
- Convenience: `document.routes(targeting: TrackID) -> [Route]` reverse filter

**Tests:**

1. New document has `routes == []`.
2. Append a route; round-trip the document; `routes.count == 1`.
3. `routes(sourcedFrom:)` returns only matching routes.
4. `routes(targeting:)` returns only routes whose destination track matches.
5. Legacy document (no `routes` key in JSON) decodes with empty list.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): routes list on project model`

---

## Task 3: `MIDIRouter` core

**Scope:** Fan-out logic given a tick-time event and a routes snapshot.

**Files:**
- Create: `Sources/Engine/MIDIRouter.swift`
- Create: `Tests/SequencerAITests/Engine/MIDIRouterTests.swift`

**API:**

```swift
public struct RouterTickInput: Equatable, Sendable {
    public let sourceTrack: TrackID
    public let notes: [NoteEvent]           // 0+ events emitted this tick
    public let chordContext: Chord?         // if this track is chord-gen sourcing
}

public protocol RouterDispatcher: AnyObject {
    // Called once per matching (route, event) pair, synchronously on the engine thread.
    func dispatch(_ event: RouterEvent)
}

public enum RouterEvent: Equatable {
    case note(to: RouteDestination, event: NoteEvent)
    case chord(to: RouteDestination, chord: Chord, lane: String?)
}

public final class MIDIRouter {
    public init(dispatcher: RouterDispatcher)

    public func applyRoutesSnapshot(_ routes: [Route])
    public func tick(_ inputs: [RouterTickInput])     // called from EngineController.tick
}
```

**Behaviour:**

- On `tick(inputs:)`:
  - For each `RouterTickInput`:
    - Find all routes whose `source` matches, filter by `enabled`, then apply the route's `RouteFilter` to each of `input.notes`.
    - For matches with `source == .track(id)`: dispatch `RouterEvent.note(to: route.destination, event: note)` for each note that passes the filter.
    - For matches with `source == .chordGenerator(id)` and `input.chordContext != nil`: dispatch `RouterEvent.chord(to: route.destination, chord: input.chordContext!, lane: ...)`.
  - If a track has `Voicing.default != .none`, the track's OWN destination is delivered separately by EngineController (not by the router) — routes are ADDITIVE.
- Routes are copy-on-write; `applyRoutesSnapshot` replaces the internal immutable list atomically.

**Tests:**

1. Empty routes, one note input → dispatcher called 0 times.
2. One route `track(A) → trackInput(B)`, one note from track A → dispatcher called once with `note(to: .trackInput(B, tag: nil), event: ...)`.
3. Two routes from the same source → dispatcher called twice (fan-out).
4. Route with `filter: .voiceTag("kick")` and notes tagged `["kick", "snare"]` → dispatcher called once (only kick match).
5. Route with `filter: .noteRange(60, 72)` and notes at pitches [55, 60, 72, 73] → dispatcher called twice.
6. `enabled = false` route → dispatcher not called.
7. `source: .chordGenerator(A)` with input `chordContext: someChord` → dispatcher called with `chord(...)`; without chord → not called.
8. `applyRoutesSnapshot([])` mid-session → next tick emits nothing.

- [ ] Tests (8 cases)
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(engine): MIDIRouter fan-out core`

---

## Task 4: `ChordContextSink` block

**Scope:** A pipeline sink that publishes the current chord-context to the router. Placed at the output of a chord-generator track's pipeline.

**Files:**
- Create: `Sources/Engine/Blocks/ChordContextSink.swift`
- Create: `Tests/SequencerAITests/Engine/ChordContextSinkTests.swift`

**Type:**

```swift
public final class ChordContextSink: Block {
    public let id: BlockID
    public static let inputs: [PortSpec] = [PortSpec(id: "chord", kind: .chord, required: true)]
    public static let outputs: [PortSpec] = []

    private let publish: (Chord) -> Void

    public init(id: BlockID, publish: @escaping (Chord) -> Void)

    public func tick(context: TickContext) -> [PortID: Stream] {
        if case .chord(let chord) = context.inputs["chord"] {
            publish(chord)
        }
        return [:]
    }

    public func apply(paramKey: String, value: ParamValue) { /* no-op */ }
}
```

**Tests:**

1. Feed `.chord(Cmaj)` into the block → `publish` is called with the chord.
2. Feed `.chord(Gmin)` → published with Gmin.
3. Feed a non-chord stream (unexpected input) → no publish, no crash.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(engine): ChordContextSink block`

---

## Task 5: Wire `MIDIRouter` into `EngineController`

**Scope:** Hold a router instance. Per tick, gather each track's note output + chord output, call `router.tick(inputs:)`. Routes are re-snapshotted when `document.routes` changes (via CommandQueue message).

**Files:**
- Modify: `Sources/Engine/EngineController.swift`
- Create (or extend): integration test in `Tests/SequencerAITests/Engine/TrackFanOutTests.swift`

**Changes:**

- `EngineController` gains a `MIDIRouter` and an internal `RouterDispatcher` implementation that routes `RouterEvent` instances to the right place (AU instrument, MIDI out, another track's input buffer, chord-context broadcast bus).
- On `document.routes` change: `router.applyRoutesSnapshot(document.routes)`.
- Per tick: collect `RouterTickInput` per track (notes emitted, chord-context if any) → `router.tick(inputs:)`.
- When a `RouterEvent.note(to: .trackInput(id, tag))` fires: enqueue the note onto that track's input buffer for its next tick to consume (back-pressure handled — if the buffer is full, drop with log).

**Tests (integration-tagged, using a mock router dispatcher where appropriate):**

1. Track A with `Voicing.default = .midi(...)` and a route `track(A) → trackInput(B)`: one note from A arrives at A's MIDI out AND on B's input buffer. (`track.midi` and route fire side-by-side.)
2. Track A with `Voicing.default = .none` and the same route: note arrives ONLY on B's input buffer. Nothing goes to MIDI out.
3. Chord-generator track C with a `ChordContextSink` → route `chordGenerator(C) → chordContext(nil)`: changing C's chord-gen params publishes to the chord-context bus.
4. Disabling the route (`enabled = false` via CommandQueue) stops delivery within 2 ticks.
5. `document.routes` change without restart: router picks it up on the next tick.

- [ ] Tests
- [ ] Implement router wiring + dispatcher
- [ ] Track input buffer handling (new internal type in EngineController; bounded ring)
- [ ] Green
- [ ] Commit: `feat(engine): MIDIRouter wired into tick; track-to-track and chord-context fan-out`

---

## Task 6: `RoutesListView` + `RouteEditorSheet`

**Scope:** Minimal UI to add / remove / edit routes. Lives in the Phrase or Track view's inspector; full matrix view is deferred.

**Files:**
- Create: `Sources/UI/RoutesListView.swift`
- Create: `Sources/UI/RouteEditorSheet.swift`
- Modify: `Sources/UI/DetailView.swift` — surface "Routes out" count near the track header; tap opens the routes list filtered to that track's sources

**Behaviour:**

- `RoutesListView` renders a table: columns = enabled-toggle, source (track name + kind), filter summary, destination (track name / MIDI / chord-context), delete button.
- `+` button opens `RouteEditorSheet`: pick source (from existing tracks), pick filter (default `.all`), pick destination (from tracks + MIDI endpoints + chord-context option).
- Saving the sheet emits a CommandQueue message `.addRoute(Route)` or `.updateRoute(id, ...)`; the EngineController router picks it up on the next tick.

**Tests:**

- Snapshot tests (qa-infrastructure plan) cover the render once baselines land.
- Behavioural:

1. Tapping "+" opens the sheet.
2. Saving a new route emits exactly one command; document's `routes` list grows by one.
3. Toggling `enabled` in the list flips the document's route.
4. Deleting a route emits `.removeRoute(id)`.
5. Route list filters by source track when entered from a track's inspector.

- [ ] Tests
- [ ] Implement the two views
- [ ] Integrate into DetailView
- [ ] Green
- [ ] Commit: `feat(ui): RoutesListView + RouteEditorSheet (inspector surface)`

---

## Task 7: Track header "Routes out" affordance

**Scope:** In the track row (Phrase view and Track detail view), show a small pill indicating how many routes source from this track. Tap opens the filtered RoutesListView.

**Files:**
- Modify: `Sources/UI/PhraseWorkspaceView.swift`, `Sources/UI/DetailView.swift`

**Behaviour:**

- Pill reads `"→ 2"` when the track is a source for 2 enabled routes; `"→ 0"` (faded) otherwise.
- Hover tooltip: "2 routes out — Bass → Lead.in; Bass → MIDI 1:ch1"
- Click opens the filtered list.

**Tests:**

1. Track with no routes: pill shows `"→ 0"` faded.
2. Add a route in the document; pill on the source track updates within a frame.
3. Click opens the filtered list (verify target view opens).

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(ui): track "Routes out" pill surfaces project routes`

---

## Task 8: Wiki update

**Scope:** `wiki/pages/routing.md` describes the Route model, the MIDIRouter's fan-out, the typical setups (chord-gen → consumers; dual MIDI out; track-to-track input), and the inspector-level UI. Update `wiki/pages/project-layout.md` for new files.

**Files:**
- Create: `wiki/pages/routing.md`
- Modify: `wiki/pages/project-layout.md`

- [ ] Wiki page
- [ ] project-layout updated
- [ ] Commit: `docs(wiki): routing page + project-layout update`

---

## Task 9: Tag + mark completed

- [ ] Replace every `- [ ]` in this file with `- [x]` for completed steps
- [ ] Add a `Status:` line after `Parent spec` in this file's header, following the placeholder-token pattern
- [ ] Commit: `docs(plan): mark midi-routing completed`
- [ ] Tag: `git tag -a v0.0.6-midi-routing -m "MIDI routing engine complete: Route model, MIDIRouter fan-out, track-to-track + chord-context routing, inspector UI"`

---

## Goal-to-task traceability (self-review)

| Goal / architectural claim | Task |
|---|---|
| `Route` value type + source/filter/destination | Task 1 |
| `document.routes: [Route]` | Task 2 |
| `MIDIRouter` fan-out core | Task 3 |
| `ChordContextSink` block | Task 4 |
| `EngineController` wires router per tick; track-to-track + chord-context | Task 5 |
| Inspector UI for routes | Task 6 |
| Track header "Routes out" pill | Task 7 |
| Wiki | Task 8 |
| Tag | Task 9 |

## Open questions resolved for this plan

- **Routes are additive, not replacement.** A track's `Voicing.default` destination fires independently of any routes. To suppress the track's own destination while routing elsewhere, set `Voicing.default = .none`. This matches the user's intended mental model: "track with no destination relies on the routing engine; track with a destination fans out to both."
- **Track input buffer:** bounded ring (16 entries) per track input tag. Overflow drops the oldest; logged. Not a spec constraint — just a sensible MVP default; revisit if we see drops in practice.
- **Chord-context broadcast bus:** one implicit bus, optionally named. `RouteDestination.chordContext(broadcastTag: nil)` is the default bus; named tags let the user run parallel chord streams (e.g. a "modal" bus and a "functional" bus that different tracks subscribe to). `quantise-to-chord` blocks (a later plan) will subscribe to a specific tag.
- **Loopbacks:** a route whose destination lands back at its source creates a feedback cycle. Router detects self-cycles at `applyRoutesSnapshot` time and warns; doesn't hard-block (the spec's `tap-prev` pattern exists for legitimate one-tick-delayed feedback). If a route ends up producing infinite events in one tick, the router caps at 256 events per tick and logs.
- **Persistence:** routes persist in the document JSON. Legacy documents (pre-routing) have no `routes` key and decode to empty.
- **Thread model:** router runs on the engine tick thread; UI edits dispatch via CommandQueue; route snapshots are immutable after `applyRoutesSnapshot`, so the router's tick loop is lock-free.
- **No UI for filter predicates beyond MVP:** the editor sheet offers `.all`, `.voiceTag`, `.noteRange` — covers the common cases. Fancier filters (time-window, velocity-range, random) are a future extension.
