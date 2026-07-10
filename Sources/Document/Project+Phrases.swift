import Foundation

extension Project {
    mutating func updatePhrase(id: UUID? = nil, _ update: (inout PhraseModel) -> Void) {
        let resolvedID = id ?? selectedPhraseID
        guard let phraseIndex = phrases.firstIndex(where: { $0.id == resolvedID }) else {
            return
        }

        update(&phrases[phraseIndex])
        phrases[phraseIndex] = phrases[phraseIndex].synced(with: tracks, layers: layers)
        selectedPhraseID = phrases[phraseIndex].id
    }

    mutating func setPhraseCell(
        _ cell: PhraseCell,
        layerID: String,
        trackIDs: [UUID],
        phraseID: UUID? = nil
    ) {
        updatePhrase(id: phraseID) { phrase in
            for trackID in trackIDs {
                phrase.setCell(cell, for: layerID, trackID: trackID)
            }
        }
    }

    mutating func setPhraseCell(_ cell: PhraseCell, at address: PhraseCellAddress) {
        setPhraseCell(
            cell,
            layerID: address.layerID,
            trackIDs: [address.trackID],
            phraseID: address.phraseID
        )
    }

    mutating func setPhraseCellMode(
        _ mode: PhraseCellEditMode,
        layer: PhraseLayerDefinition,
        trackIDs: [UUID],
        phraseID: UUID? = nil
    ) {
        updatePhrase(id: phraseID) { phrase in
            for trackID in trackIDs {
                phrase.setCellMode(mode, for: layer, trackID: trackID)
            }
        }
    }

    mutating func appendPhrase() {
        var nextPhrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: generatorPool,
            clipPool: clipPool
        )
        nextPhrase.id = UUID()
        nextPhrase.name = Self.defaultPhraseName(for: phrases.count)
        phrases.append(nextPhrase.synced(with: tracks, layers: layers))
        selectedPhraseID = nextPhrase.id
    }

    mutating func insertPhrase(below phraseID: UUID) {
        guard let index = phrases.firstIndex(where: { $0.id == phraseID }) else {
            appendPhrase()
            return
        }

        var nextPhrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: generatorPool,
            clipPool: clipPool
        )
        nextPhrase.id = UUID()
        nextPhrase.name = Self.defaultPhraseName(for: phrases.count)
        let insertionIndex = min(index + 1, phrases.count)
        phrases.insert(nextPhrase.synced(with: tracks, layers: layers), at: insertionIndex)
        selectedPhraseID = nextPhrase.id
    }

    mutating func duplicateSelectedPhrase() {
        guard !phrases.isEmpty else {
            return
        }

        var duplicate = selectedPhrase
        duplicate.id = UUID()
        duplicate.name = "\(selectedPhrase.name) Copy"
        let insertionIndex = min(selectedPhraseIndex + 1, phrases.count)
        phrases.insert(duplicate.synced(with: tracks, layers: layers), at: insertionIndex)
        selectedPhraseID = duplicate.id
    }

    mutating func duplicatePhrase(id phraseID: UUID) {
        guard let index = phrases.firstIndex(where: { $0.id == phraseID }) else {
            return
        }

        _ = insertPhraseCopy(phrases[index], below: phraseID)
    }

    /// Insert a detached phrase snapshot below a live target. Every insertion
    /// receives a fresh identity so repeated pastes remain independent.
    @discardableResult
    mutating func insertPhraseCopy(_ snapshot: PhraseModel, below targetPhraseID: UUID) -> UUID? {
        guard let targetIndex = phrases.firstIndex(where: { $0.id == targetPhraseID }) else {
            return nil
        }

        var duplicate = snapshot
        duplicate.id = UUID()
        duplicate.name = "\(snapshot.name) Copy"
        let insertionIndex = min(targetIndex + 1, phrases.count)
        phrases.insert(duplicate.synced(with: tracks, layers: layers), at: insertionIndex)
        selectedPhraseID = duplicate.id
        return duplicate.id
    }

    mutating func removeSelectedPhrase() {
        guard phrases.count > 1 else {
            return
        }

        phrases.remove(at: selectedPhraseIndex)
        selectedPhraseID = phrases[min(selectedPhraseIndex, phrases.count - 1)].id
    }

    mutating func removePhrase(id phraseID: UUID) {
        guard phrases.count > 1,
              let index = phrases.firstIndex(where: { $0.id == phraseID }) else {
            return
        }

        phrases.remove(at: index)
        let nextIndex = min(index, phrases.count - 1)
        selectedPhraseID = phrases[nextIndex].id
    }

    private static func defaultPhraseName(for index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        if alphabet.indices.contains(index) {
            return "Phrase \(alphabet[index])"
        }
        return "Phrase \(index + 1)"
    }
}
