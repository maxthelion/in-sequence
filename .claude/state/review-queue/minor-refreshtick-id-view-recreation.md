# 🔵 Minor — `PreferencesView.MIDIPreferences` uses `.id(refreshTick)` to force re-evaluation, which destroys/recreates the whole view tree

**File:** `Sources/UI/PreferencesView.swift:73-77`

## What's wrong

```swift
Button("Refresh") { refreshTick += 1 }
…
.id(refreshTick)
```

`.id(refreshTick)` is the SwiftUI "nuke and replace" escape hatch — when `id` changes, SwiftUI treats the view as an entirely new identity, deallocates the old subtree, and rebuilds from scratch. It works, but it's a heavier hammer than needed:

- All transient state inside the tree (scroll position, selection, in-flight animations) is lost on refresh.
- The view hierarchy is fully re-allocated, which for a `Form` with `ForEach` over potentially dozens of endpoints is non-free.

The comment above it correctly says observation-driven invalidation is the right long-term fix (when `MIDIClient` subscribes to `kMIDIMsgObjectAdded/Removed`), and a TODO is in place. Good. But as a **temporary hack**, `.id(refreshTick)` is a bigger hammer than required.

## What would be right

Two lighter options:

- **Bind the view to `refreshTick` via a computed dependency instead of `.id`.** Read `refreshTick` as part of computing `sources` / `destinations`:
  ```swift
  let _ = refreshTick  // triggers re-evaluation of body
  let session = MIDISession.shared
  Form { … ForEach(session.sources) { … } … }
  ```
  The explicit `_` read makes the dependency legible and doesn't nuke child identity.
- **Store snapshots in `@State`.** On Refresh, read `session.sources` / `session.destinations` into local `@State` arrays and display those. Cheaper; also makes the refresh semantics explicit.

Neither is a big lift; both preserve the long-term plan (swap for observation-driven once MIDIClient mutates tracked state).

## Why it matters

Low-stakes today because the preferences window is rarely open and the endpoint list is short. But the pattern `.id(counter)` tends to propagate — a junior author sees it work, copies it elsewhere, and over time the codebase accumulates view-recreation hammers where narrow bindings would do. Cheaper to correct the precedent now than later.
