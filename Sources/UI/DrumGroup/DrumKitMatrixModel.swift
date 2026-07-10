import Foundation

/// Transient template-target selection for the kit pattern palette. It never
/// enters the document: a normal secondary click replaces the target set,
/// Shift-secondary-click adds to it, and an Apply request with no targets
/// enters the visual prompt state instead of guessing at the active pattern.
struct DrumKitPatternTargetSelection: Equatable {
    private(set) var slotIndexes: Set<Int> = []
    private(set) var isPrompting = false

    mutating func select(slotIndex: Int, additive: Bool) {
        guard (0..<TrackPatternBank.slotCount).contains(slotIndex) else { return }
        if additive {
            slotIndexes.insert(slotIndex)
        } else {
            slotIndexes = [slotIndex]
        }
        isPrompting = false
    }

    /// Returns whether the chooser should open now.
    @discardableResult
    mutating func requestTemplateChooser() -> Bool {
        guard !slotIndexes.isEmpty else {
            isPrompting = true
            return false
        }
        isPrompting = false
        return true
    }

    mutating func clear() {
        slotIndexes = []
        isPrompting = false
    }
}

/// Keeps the segmented Fill control honest when its backing source becomes
/// unavailable. A stale engine flag must not leave a disabled Fill segment
/// looking selected.
struct DrumKitFillModePresentation: Equatable {
    let isAvailable: Bool
    let requestedFill: Bool

    var isFillSelected: Bool {
        isAvailable && requestedFill
    }
}

/// Pure value/derivation model for the kit matrix. Resolves a drum group's
/// members into ordered rows, each carrying its active pattern slot's content
/// (editable note grid, generator badge, or read-only source), plus the
/// group-level shared pattern slot. Holds no SwiftUI — it is built from store
/// snapshots and is unit-testable in isolation.
///
/// Patterns are GLOBAL across the kit: selecting a slot fans the same index to
/// every member, so members never diverge through the UI. The former per-kit
/// "pattern mismatch" / "link broken" / per-row divergence badges modelled an
/// older per-kit-pattern design and have been removed.
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
        var defaultNote: ClipStepNote

        var patternBadge: String {
            "P\(patternSlotIndex + 1)"
        }

        var isEditable: Bool {
            if case .editable = content { return true }
            return false
        }

        /// The active source's length in steps, when it is a note-grid clip the
        /// row can express. `nil` for generator/read-only rows that have no
        /// fixed step length to surface.
        var clipLengthSteps: Int? {
            switch content {
            case let .editable(_, lengthSteps, _):
                return lengthSteps
            case .generator, .readOnly:
                return nil
            }
        }

        /// Compact clip-length line shown under the part name, e.g. "1 bar · 16
        /// steps". Returns `nil` for rows with no expressible step length.
        var clipLengthLabel: String? {
            guard let steps = clipLengthSteps, steps > 0 else { return nil }
            let stepsPerBar = 16
            let bars = max(1, Int((Double(steps) / Double(stepsPerBar)).rounded(.up)))
            let barWord = bars == 1 ? "bar" : "bars"
            let stepWord = steps == 1 ? "step" : "steps"
            return "\(bars) \(barWord) · \(steps) \(stepWord)"
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

    var memberCountLabel: String {
        "\(rows.count) part\(rows.count == 1 ? "" : "s")"
    }

    /// The shared pattern slot for the whole kit. Patterns are global, so the
    /// kit selects ONE slot for all members; this resolves to the first row's
    /// slot. (Legacy documents may carry per-member divergence; the slot
    /// binding's first write re-aligns every member.)
    var groupSelectedSlotIndex: Int? {
        rows.first?.patternSlotIndex
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

        self.groupID = group.id
        self.groupName = group.name
        self.colorHex = group.color
        self.originatingPartID = originatingPartID
        self.displayStepCount = resolvedDisplayStepCount
        self.staleMemberCount = staleMemberCount
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
