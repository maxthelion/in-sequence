import Foundation

extension SequencerDocumentSession {
    /// Switch every resolved member of a drum group to pattern slot `index`.
    ///
    /// This is a convenience fan-out of the existing per-track
    /// `setSelectedPatternIndex(_:for:)` — the same phrase-cell write per
    /// member, batched so the engine sees one snapshot update. There is no
    /// persisted group-pattern object.
    func setDrumGroupSelectedPatternIndex(_ index: Int, groupID: TrackGroupID) {
        batch(impact: .snapshotOnly, changed: .phrase(store.selectedPhraseID)) { s in
            var p = s.exportToProject()
            guard let group = p.trackGroups.first(where: { $0.id == groupID }) else { return }
            let trackIDs = Set(p.tracks.map(\.id))
            for memberID in group.memberIDs where trackIDs.contains(memberID) {
                p.setSelectedPatternIndex(index, for: memberID)
            }
            s.replacePhrases(p.phrases, selectedPhraseID: p.selectedPhraseID)
        }
    }

    /// Apply a pattern template to a drum group as ONE batched, undoable
    /// mutation. Wraps `Project.applyPatternTemplate` — the same
    /// implementation the creation path uses — so matched members get fresh
    /// clip-pool entries in the target slot, generator-backed slots are
    /// skipped, and duplicate tags fill the first occurrence only.
    ///
    /// - Returns: `true` when the apply changed anything.
    @discardableResult
    func applyPatternTemplate(
        _ template: PatternTemplate,
        toGroup groupID: TrackGroupID,
        slotIndex: Int
    ) -> Bool {
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.applyPatternTemplate(template, toGroup: groupID, slotIndex: slotIndex)
            s.importFromProject(p)
        }
    }
}
