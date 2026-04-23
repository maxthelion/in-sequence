import Foundation
@testable import SequencerAI

// MARK: - Test-only bridge for SequencerDocumentSession
//
// These helpers allow existing test code to use the familiar
// `session.mutateProject { project in ... }` pattern without
// the production code being exposed to the full-project bridge.
//
// New test code should prefer the typed session API directly.

extension SequencerDocumentSession {

    /// Test-only bridge: exports, applies closure, imports, dispatches impact.
    ///
    /// Existing tests that were written against the old production bridge use this.
    /// New tests should call the typed session mutation methods directly.
    @discardableResult
    func mutateProject(
        impact: LiveMutationImpact = .snapshotOnly,
        _ update: (inout Project) -> Void
    ) -> Bool {
        var p = store.exportToProject()
        let before = p
        update(&p)
        guard p != before else { return false }
        store.importFromProject(p)
        revision = store.revision

        switch impact {
        case .snapshotOnly:
            publishSnapshot()
        case .fullEngineApply:
            engineController.apply(documentModel: store.exportToProject())
        case .scopedRuntime(let update):
            dispatchScopedRuntimeUpdate(update)
            publishSnapshot()
        }

        scheduleFlushToDocument()
        return true
    }
}
