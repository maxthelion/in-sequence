import XCTest
@testable import SequencerAI

// MARK: - Export-to-project spy helpers
//
// Use these helpers in tests that assert a code path does NOT call
// `exportToProject()` — the main performance invariant introduced in
// the live-store v2 remediation.

/// Assert that `exportToProject()` is not called on `store` during `block`.
///
/// Captures `exportToProjectCallCount` before running `block`, then asserts
/// the count has not advanced after `block` returns.
@MainActor
func assertNoExportDuring(
    _ store: LiveSequencerStore,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ block: () -> Void
) {
    let before = store.exportToProjectCallCount
    block()
    let after = store.exportToProjectCallCount
    XCTAssertEqual(
        after,
        before,
        "exportToProject() was called \(after - before) time(s) during block — expected 0",
        file: file,
        line: line
    )
}
