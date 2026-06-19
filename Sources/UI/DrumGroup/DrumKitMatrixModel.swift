import Foundation

/// Pure value/derivation model for the kit matrix. Resolves a drum group's
/// members into ordered rows, each carrying its active pattern slot's content
/// (editable note grid, generator badge, or read-only source), plus group-level
/// derivations (pattern mismatch, shared slot, link-broken state). Holds no
/// SwiftUI — it is built from store snapshots and is unit-testable in isolation.
struct DrumKitMatrixModel: Equatable {
    struct Row: Identifiable, Equatable {
        /// What the row's active pattern slot resolves to.
        enum Content: Equatable {
            /// Note-grid clip (or empty clip slot — materialized on first
            /// edit, exactly like the single-track editor).
            case editable(clipID: UUID?, lengthSteps: Int, steps: [ClipStep])
            /// Generator-backed slot: generator badge, read-only cells,
            /// no inline editing (v1 conservative treatment).
            case generator(detail: String)
            /// Clip content the step grid cannot represent (slice triggers).
            case readOnly(badge: String, detail: String, steps: [Bool])
        }

        var id: UUID { memberID }

        var memberID: UUID
        var partName: String
        var patternSlotIndex: Int
        var sourceMode: TrackSourceMode
        var content: Content
        var isDivergentPattern: Bool
        var defaultNote: ClipStepNote

        var patternBadge: String {
            "P\(patternSlotIndex + 1)"
        }

        var isEditable: Bool {
            if case .editable = content { return true }
            return false
        }
    }

    var groupID: TrackGroupID
    var groupName: String
    var colorHex: String
    var originatingPartID: UUID
    var displayStepCount: Int
    var rows: [Row]
    var staleMemberCount: Int
    /// Pattern slots where at least one member holds a non-empty source.
    var occupiedSlotIndexes: Set<Int>
    /// The group's explicit pattern-link intent (AC17). Linking gangs pattern
    /// slot selection only; mute/fill/macros stay per-part.
    var isPatternLinked: Bool

    var memberCountLabel: String {
        "\(rows.count) part\(rows.count == 1 ? "" : "s")"
    }

    var hasPatternMismatch: Bool {
        rows.contains(where: \.isDivergentPattern)
    }

    /// The slot every member shares, or nil when members diverge (mixed state).
    var groupSelectedSlotIndex: Int? {
        guard let first = rows.first?.patternSlotIndex else { return nil }
        return rows.allSatisfy { $0.patternSlotIndex == first } ? first : nil
    }

    /// Structural divergence (AC20): the kit intends to be linked, but members
    /// sit on different pattern slots, so the link is effectively broken until
    /// re-linked. This is the condition that surfaces the one-click "Re-link".
    var isLinkBroken: Bool {
        isPatternLinked && groupSelectedSlotIndex == nil && rows.count > 1
    }

    init?(
        groupID: TrackGroupID,
        originatingPartID: UUID,
        displayStepCount: Int,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup],
        layers: [PhraseLayerDefinition],
        selectedPhrase: PhraseModel,
        patternBanks: [TrackPatternBank],
        clipPool: [ClipPoolEntry],
        generatorPool: [GeneratorPoolEntry]
    ) {
        guard let group = trackGroups.first(where: { $0.id == groupID }) else {
            return nil
        }

        let resolvedDisplayStepCount = displayStepCount == 32 ? 32 : 16
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var seenMemberIDs: Set<UUID> = []
        let orderedMembers = group.memberIDs.compactMap { memberID -> StepSequenceTrack? in
            guard seenMemberIDs.insert(memberID).inserted else { return nil }
            return tracksByID[memberID]
        }
        let resolvedMemberIDs = Set(orderedMembers.map(\.id))
        let staleMemberCount = Set(group.memberIDs).subtracting(resolvedMemberIDs).count
        let firstPatternSlot = orderedMembers.first.map {
            selectedPhrase.patternIndex(for: $0.id, layers: layers)
        }

        self.groupID = group.id
        self.groupName = group.name
        self.colorHex = group.color
        self.originatingPartID = originatingPartID
        self.displayStepCount = resolvedDisplayStepCount
        self.staleMemberCount = staleMemberCount
        self.isPatternLinked = group.isPatternLinked
        self.rows = orderedMembers.map { track in
            let patternSlotIndex = selectedPhrase.patternIndex(for: track.id, layers: layers)
            let patternBank = Self.patternBank(
                for: track,
                patternBanks: patternBanks,
                clipPool: clipPool
            )
            let patternSlot = patternBank.slot(at: patternSlotIndex)
            return Row(
                memberID: track.id,
                partName: track.name,
                patternSlotIndex: patternSlotIndex,
                sourceMode: patternSlot.sourceRef.mode,
                content: Self.content(
                    patternSlot: patternSlot,
                    clipPool: clipPool,
                    generatorPool: generatorPool
                ),
                isDivergentPattern: firstPatternSlot.map { patternSlotIndex != $0 } ?? false,
                defaultNote: ClipStepNote(
                    pitch: track.pitches.first ?? 60,
                    velocity: track.velocity,
                    lengthSteps: track.gateLength
                ).normalized
            )
        }
        self.occupiedSlotIndexes = Self.occupiedSlots(
            members: orderedMembers,
            patternBanks: patternBanks,
            clipPool: clipPool
        )
    }

    private static func patternBank(
        for track: StepSequenceTrack,
        patternBanks: [TrackPatternBank],
        clipPool: [ClipPoolEntry]
    ) -> TrackPatternBank {
        if let existing = patternBanks.first(where: { $0.trackID == track.id }) {
            return existing
        }
        let fallbackClipID = clipPool.first(where: { $0.trackType == track.trackType })?.id
        return TrackPatternBank.default(for: track, initialClipID: fallbackClipID)
    }

    private static func content(
        patternSlot: TrackPatternSlot,
        clipPool: [ClipPoolEntry],
        generatorPool: [GeneratorPoolEntry]
    ) -> Row.Content {
        switch patternSlot.sourceRef.mode {
        case .generator:
            if let generator = generatorPool.first(where: { $0.id == patternSlot.sourceRef.generatorID }) {
                return .generator(detail: generator.name)
            }
            return .generator(detail: "Generator unavailable")
        case .clip:
            guard let clipID = patternSlot.sourceRef.clipID,
                  let clip = clipPool.first(where: { $0.id == clipID })
            else {
                // Empty slot: render an empty 16-step grid; the first edit
                // materializes a clip through `ensureClipAndMutate`. (The
                // single-track editor never edits an empty slot — its clip
                // panel only shows for an occupied clip — so the matrix is
                // the one surface that still needs the slot-address key.)
                return .editable(
                    clipID: nil,
                    lengthSteps: 16,
                    steps: Array(repeating: .empty, count: 16)
                )
            }
            let normalized = clip.content.normalized
            guard let steps = normalized.noteGridSteps,
                  let lengthSteps = normalized.noteGridLengthSteps
            else {
                let pattern: [Bool]
                if case let .sliceTriggers(stepPattern, _, _, _) = normalized {
                    pattern = stepPattern
                } else {
                    pattern = []
                }
                return .readOnly(badge: "RO", detail: "Read-only source", steps: pattern)
            }
            return .editable(clipID: clip.id, lengthSteps: lengthSteps, steps: steps)
        }
    }

    private static func occupiedSlots(
        members: [StepSequenceTrack],
        patternBanks: [TrackPatternBank],
        clipPool: [ClipPoolEntry]
    ) -> Set<Int> {
        let clipsByID = Dictionary(uniqueKeysWithValues: clipPool.map { ($0.id, $0) })
        var occupied: Set<Int> = []
        for member in members {
            let bank = patternBank(for: member, patternBanks: patternBanks, clipPool: clipPool)
            for slot in bank.slots where !occupied.contains(slot.slotIndex) {
                switch slot.sourceRef.mode {
                case .generator:
                    if slot.sourceRef.generatorID != nil {
                        occupied.insert(slot.slotIndex)
                    }
                case .clip:
                    if let clipID = slot.sourceRef.clipID,
                       let clip = clipsByID[clipID],
                       !clipIsEmpty(clip.content) {
                        occupied.insert(slot.slotIndex)
                    }
                }
            }
        }
        return occupied
    }
}
