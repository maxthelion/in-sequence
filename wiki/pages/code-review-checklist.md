---
title: "Code Review Checklist"
category: "meta"
tags: [review, standards, contracts, boundaries, testing, quality]
summary: Project-specific review standards enforcing clear contracts, focused files, and contract-boundary testing. Complements the generic superpowers:code-reviewer pass.
last-modified-by: user
---

Project-specific review standards for `sequencer-ai`. Complements (does not replace) the generic quality review done by `superpowers:code-reviewer`.

**When to use this:** every pull request, every spec-reviewer pass, every self-review before committing. A change doesn't ship unless each applicable item is answerable with a clear *yes* or a deliberate, documented *no*.

The three invariants this defends:

1. **Every unit has a clear contract.** You can state in one sentence what it does, what it accepts, what it returns, what it promises about side effects.
2. **No god files.** A file does one thing. When it starts doing two, split it.
3. **Every contract is tested at its boundary.** Tests verify observable behavior through the public surface, not internal implementation.

---

## 1. Contract & boundary

The most load-bearing checks.

- [ ] **One-sentence description.** Can you state what this unit does in one sentence that doesn't use "and", "or", or "also"? If not, it's doing too much.
- [ ] **Explicit interface.** The public surface (public/internal methods, properties, types) is the contract. Everything else is `private` or `fileprivate`. Is everything that leaks out into the public surface intentional?
- [ ] **Input contract.** What inputs does the unit accept? Preconditions stated or enforced? Types narrow enough to make illegal states unrepresentable?
- [ ] **Output contract.** What does it return / produce / cause? Postconditions clear? No returning sentinels (`-1`, empty string, `Int.max`) in place of a proper optional / `Result` / typed error.
- [ ] **Side effect contract.** Does it touch filesystem, network, MIDI, audio, global state? Is that side effect obvious from the name? `createDirectory` is fine; `getThings` that also writes to disk is not.
- [ ] **Error contract.** Which errors can leak out? Are they typed (`throw`/`Result`) or do they crash / silently drop? No `try?` swallowing real failures.
- [ ] **Threading contract.** Is it safe to call from any thread, only main, or only the audio render thread? Documented. Enforced with `@MainActor` / dispatch / actor isolation when possible, not by hope.
- [ ] **Ownership contract.** What lifetime does this unit have? Who creates it, who destroys it? For types managing OS resources (CoreMIDI refs, AudioUnits, file handles), cleanup is in `deinit` or an explicit `close()` — no resource leaks.

**Signals a contract isn't clear:**
- The call site reads the implementation to know what happens
- You need to grep for usages to understand behavior
- "It depends" is the honest answer to "what does this return?"
- Reviewer has to read two files at once to evaluate one

---

## 2. No god files

- [ ] **One responsibility per file.** Not "one class per file" — *one responsibility*. A file that exposes `Foo`, `FooCache`, `FooPolicy`, `FooError`, and 3 helper functions has 5 responsibilities.
- [ ] **Line count is a smell, not a rule.** ~200 lines is fine; ~500 lines is a smell; ~1000 lines means split unless the responsibility genuinely is that big (rare). Growth since the file was created matters more than absolute size.
- [ ] **Import surface.** If a file imports half the codebase, it's probably wiring too many concerns together. Consider moving the wiring to a dedicated composition-root file.
- [ ] **The "test name" test.** If you can't name a test for this file in the form `test_<fileSubject>_does_<specificBehavior>()` without the test name getting absurd, the file has too many subjects.
- [ ] **Utilities folder pressure.** Don't create `Utils.swift` / `Helpers.swift`. Every utility belongs somewhere with a real name. If it doesn't fit anywhere, you haven't named the responsibility yet.
- [ ] **Avoid "kitchen-sink service" types.** A class with a dozen methods that operate on loosely-related concerns is a structural failure. Break it into focused collaborators that the caller composes.

**Our scaffold's precedent (what good looks like):**
- `MIDIClient.swift` — wraps a CoreMIDI client and owns its virtual endpoints. One responsibility. ~90 lines.
- `MIDIEndpoint.swift` — value type for an endpoint. One responsibility. ~30 lines.
- `MIDISession.swift` — app-level singleton that composes a `MIDIClient` with the two virtual endpoints. One responsibility (composition). ~45 lines.
- `AppSupportBootstrap.swift` — creates a specific directory tree. One responsibility. ~30 lines.

Note how MIDI is three files, not one `MIDIEverything.swift`. That's the pattern.

---

## 3. Testing contracts

- [ ] **Test through the public surface.** Tests call the same methods / properties consumers would. Tests that reach into `private` state (via `@testable` hacks, reflection, test-only accessors) are testing implementation, not contract.
- [ ] **One assertion per behavior.** A test verifies one observable outcome. If a test needs three `XCTAssertEqual` lines they'd better be verifying *one* composite behavior (e.g., all three components of a `Step` that must match together).
- [ ] **Tests can fail.** A test that passes regardless of the implementation (because the fallback path is always taken, because the assertion is tautological, because the mock returns whatever the test expects) is not a test. See the `MIDIEndpoint` init-fallback noted in the Plan 0 code-quality review: the display-name fallback to `"Unknown MIDI Endpoint"` made `test_endpoint_has_non_empty_display_name_when_present` tautological. Fix by asserting the value isn't the fallback, or remove the fallback.
- [ ] **Tests describe what, not how.** Test name says "what behavior is verified" (`test_empty_document_has_version_1`), not "how it works internally" (`test_initializer_calls_encoder`).
- [ ] **Behavior, not mocks.** Prefer real implementations when feasible (filesystem, CoreMIDI, real Codable). Mocks are a last resort for unavailable or slow dependencies (network, external APIs). Mock reality → tests pass while production breaks.
- [ ] **No test-only code paths in production.** No `#if DEBUG`-gated overrides used by tests. If you need to inject a dependency to test it, inject it always.
- [ ] **Idempotency is tested.** Any operation that claims "safe to call twice" (bootstrap, setup, teardown) has a test that calls it twice.
- [ ] **Error paths are tested.** Not just "happy path returns X"; also "invalid input throws Y". Typed errors give you test leverage — use it.
- [ ] **Boundary semantics are tested.** Empty list, single item, max-size list. Off-by-one happens at boundaries.
- [ ] **The contract test suite is runnable in isolation.** `xcodebuild test` passes on a clean checkout with no hidden ordering / state dependencies between tests.

---

## 4. Dependencies & coupling

- [ ] **Dependencies flow inward.** Domain → platform → UI, not the other way. `SeqAIDocumentModel` shouldn't know about SwiftUI. `MIDIClient` shouldn't know about `@Observable`. Core engine shouldn't depend on audio engine.
- [ ] **Hard-coded singletons are a cost.** `MIDISession.shared` is fine at the app-composition boundary; lower-level code shouldn't reach for it. Pass the session (or what's actually needed) explicitly.
- [ ] **No hidden coupling via globals.** Mutable global state is a coupling surface that isn't documented anywhere. If something needs shared state, name the sharer.
- [ ] **Interfaces are smaller than implementations.** Callers take the narrow interface (`protocol MIDIOutput { func send(_: …) }`) not the concrete class. Easier to test, easier to replace, easier to reason about.
- [ ] **Circular dependencies stay forbidden.** A imports B imports A = refactor. Our pipeline DAG forbids cycles; the same applies at the module level.

---

## 5. Naming & intent

- [ ] **Names describe *what*, not *how*.** `sources` and `destinations` in `MIDIClient` describe what CoreMIDI exposes — not how it enumerates them. `clearLayers()` not `iterateAndNull()`.
- [ ] **No misleading names.** `getUser()` that also creates the user on first call is lying. Rename or split.
- [ ] **Uniform vocabulary.** Same concept, same name, everywhere. The `sources`/`destinations`/`Role`/`createVirtualOutput/Input` naming was made uniform in commit `d33c72f` after an early inconsistency. Do that kind of cleanup promptly.
- [ ] **Avoid abbreviations that aren't universal.** `cfg`, `ctx`, `mgr`, `svc` outside of very tight scopes. `configuration`, `context`, `manager`, `service` — costs are zero, clarity gains are real.
- [ ] **Don't start types with `I` (Swift idiom).** Protocols get the noun name, concrete classes get the adjective or role (`MIDIOutput` protocol, `VirtualMIDIOutput` class).

---

## 6. Safety & error handling

- [ ] **Crashes only on programmer error.** `fatalError` / `precondition` is fine for impossible states (programmer bug). User inputs / external APIs / filesystem / MIDI / network never justify `fatalError`.
- [ ] **Typed errors, not error messages.** `throw ClientError.failedToCreateClient(status: status)` beats `throw NSError(domain: "midi", …)`. Callers can handle specific cases.
- [ ] **No silent failures.** A `try?` that ignores a genuine error is a silent failure. Either handle it, surface it to the user, or log it with context. `NSLog` at least leaves breadcrumbs.
- [ ] **Resource ownership is explicit.** Every `MIDIClientRef` / `MIDIEndpointRef` / `AUAudioUnit` / file handle / socket has a known owner that disposes of it in `deinit` or explicit teardown. Leaks here are days of hair-pulling later.
- [ ] **Thread-safety is declared and enforced.** If a type is main-thread-only, mark it `@MainActor`. If it's an actor, make it one. If it's supposed to be called from the audio render thread, document the allocation-free / lock-free requirement. Mismatches here are the hardest bugs in this codebase.

---

## 7. Realtime-audio specific (once we get there)

The pipeline executor will run on the audio render thread. Rules for any code that ends up there:

- [ ] **No allocation.** No `String`, no `Array.append` that could grow, no `Dictionary` mutation. Pre-allocate and reuse.
- [ ] **No locking.** No `DispatchSemaphore`, no `NSLock`, no `@synchronized`. Use lock-free structures (atomics, ring buffers).
- [ ] **No Swift runtime overhead.** No reflection, no protocol witness table dispatch in hot paths, no `Any`. Prefer generics that specialize, or concrete types.
- [ ] **No Objective-C / CF calls.** Both take locks internally.
- [ ] **UI thread → render thread communication is a ring buffer.** Command objects written by UI, consumed by render thread. Never the other direction synchronously.
- [ ] **Render thread → UI thread is a ring buffer, read on display link.** Never the render thread calling back into UI.
- [ ] **Tests for timing.** Benchmark the render callback. Know its worst-case cost. Regression-test it.

---

## 8. Procedure

- [ ] **TDD when feasible.** Write the failing test first; make it pass minimally; refactor. The scaffold follows this pattern throughout.
- [ ] **Small, reviewable commits.** One logical change per commit. Our Plan 0 history is 11 commits, each buildable and testable in isolation — that's the bar.
- [ ] **Every test passes before commit.** `xcodebuild test` green. No skipped or disabled tests committed without a linked issue.
- [ ] **Every behavior change is tested.** New features have tests. Bug fixes have a test that would have caught the bug. Refactors change zero behavior and zero tests (except test-name renames).
- [ ] **Dead code gets deleted, not commented out.** Version control remembers.
- [ ] **The plan's checkboxes are ticked honestly.** Don't mark a step `[x]` without actually completing it. If a step is blocked or skipped, explain why in the commit or a note on the step.

---

## 9. Specific Swift / SwiftUI review items

- [ ] **`let` over `var`.** Stored properties that are never reassigned should be `let`. Found a `var` that could be `let` in post-review? Downgrade it.
- [ ] **`@Observable` over `ObservableObject`** on macOS 14+ / iOS 17+.
- [ ] **`@Observable` computed properties need backing stored state.** A computed property on an `@Observable` type only triggers view re-renders when its dependencies are stored-tracked; if it reads external state (like enumerating CoreMIDI sources on every access), observation won't fire. Use explicit invalidation (refresh trigger, notification) — and document the choice.
- [ ] **Structured concurrency over callbacks.** `async`/`await` over completion handlers for new code. Exception: CoreMIDI / AudioUnit callbacks that the OS invokes — those stay as callbacks and marshal into `Task` at the boundary.
- [ ] **`final` by default for classes.** Open inheritance is an intentional API decision; closed is the default.
- [ ] **No implicitly unwrapped optionals.** `var x: Foo!` is a cost center. Either the value is always non-nil (make it non-optional, initialize in `init`) or it's sometimes nil (make it `Foo?` and handle both paths).
- [ ] **Equatable / Hashable conformances justified.** Auto-synthesis is fine but ask whether two instances really *are* equal when all fields match.

---

## 10. Red flags — immediate reject

If any of these appear, the change isn't ready:

- New file named `Utils*.swift`, `Helpers*.swift`, `Common*.swift`, `Core*.swift` (with no scoped meaning), `Manager*.swift` with >5 methods, `*Singleton.swift`
- A public API takes or returns `[String: Any]`
- A function longer than ~50 lines without an explicit reason
- A test file with only `setUp` / `tearDown` code paths exercised
- A test without an assertion
- A commit message of the form "fix stuff" / "wip" / "updates"
- Tests mutated to make previously-failing assertions pass (rather than fixing the code they test)
- A `FIXME` without an owner or linked issue
- Silent `catch { }` blocks
- Magic numbers that aren't named constants
- A "just this once" deviation from the standards in this doc — the precedent compounds

---

## Using this checklist

For your own work: run the checklist in section 2 (file size) and 3 (testing) at commit time. Run the others at PR / merge-to-main time.

For reviewing others: every Important/Critical-severity issue in a code review should map to an item in this list. If it doesn't, consider whether the list needs a new item.

For `superpowers:code-reviewer` agent runs: attach this file's path to the review prompt so the reviewer's judgments are grounded in our standards, not generic ones.

The list is evolving — add items when we find patterns worth enforcing; remove items that stop pulling weight.
