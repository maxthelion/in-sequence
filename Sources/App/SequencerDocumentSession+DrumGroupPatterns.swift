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

    /// Set a drum group's explicit pattern-slot link flag (AC17). Linking gangs
    /// PATTERN SLOT SELECTION only; mute, fill, and macros stay per-part, so
    /// this only flips the flag — it does not touch any member's mute/fill/
    /// macros. Turning linking ON does not by itself realign members; use
    /// `reLinkDrumGroupPattern` (or selecting a group slot) to re-gang.
    @discardableResult
    func setDrumGroupPatternLinked(_ linked: Bool, groupID: TrackGroupID) -> Bool {
        batch(impact: .snapshotOnly, changed: .full) { s in
            _ = s.mutateTrackGroup(id: groupID) { group in
                group.isPatternLinked = linked
            }
        }
    }

    /// Re-link a drum group whose members have structurally diverged (AC20):
    /// re-gang every resolved member to the group's representative pattern slot
    /// (the first member's current slot) and mark the group linked again. This
    /// is the one-click "Re-link" affordance. Pattern slot selection only — it
    /// never touches mute/fill/macros.
    func reLinkDrumGroupPattern(groupID: TrackGroupID) {
        batch(impact: .snapshotOnly, changed: .full) { s in
            var p = s.exportToProject()
            p.reLinkDrumGroupPattern(groupID: groupID)
            s.importFromProject(p)
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
