import Foundation

struct ChordPaletteSlot: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var root: Int
    var chordID: ChordID
    var scaleID: ScaleID

    init(
        id: UUID = UUID(),
        name: String,
        root: Int,
        chordID: ChordID,
        scaleID: ScaleID = .major
    ) {
        self.id = id
        self.name = name
        self.root = min(max(root, 0), 127)
        self.chordID = chordID
        self.scaleID = scaleID
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        let rootName = ChordPalette.pitchName(for: root)
        let quality = ChordDefinition.for(id: chordID)?.name ?? chordID.rawValue
        return "\(rootName) \(quality)"
    }

    var normalized: ChordPaletteSlot {
        ChordPaletteSlot(
            id: id,
            name: name,
            root: root,
            chordID: chordID,
            scaleID: scaleID
        )
    }
}

struct ChordPalette: Codable, Equatable, Hashable, Sendable {
    var slots: [ChordPaletteSlot]
    var selectedSlotID: UUID?

    init(slots: [ChordPaletteSlot] = Self.defaultSlots, selectedSlotID: UUID? = nil) {
        let resolvedSlots = slots.isEmpty ? Self.defaultSlots : slots.map(\.normalized)
        self.slots = resolvedSlots
        self.selectedSlotID = selectedSlotID.flatMap { id in
            resolvedSlots.contains(where: { $0.id == id }) ? id : nil
        } ?? resolvedSlots.first?.id
    }

    static let defaultSlots: [ChordPaletteSlot] = [
        ChordPaletteSlot(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccc01") ?? UUID(),
            name: "I",
            root: 60,
            chordID: .majorTriad,
            scaleID: .major
        ),
        ChordPaletteSlot(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccc02") ?? UUID(),
            name: "IV",
            root: 65,
            chordID: .majorTriad,
            scaleID: .major
        ),
        ChordPaletteSlot(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccc03") ?? UUID(),
            name: "V",
            root: 67,
            chordID: .majorTriad,
            scaleID: .major
        ),
        ChordPaletteSlot(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccc04") ?? UUID(),
            name: "vi",
            root: 69,
            chordID: .minorTriad,
            scaleID: .major
        ),
    ]

    static let `default` = ChordPalette()

    var normalized: ChordPalette {
        ChordPalette(slots: slots, selectedSlotID: selectedSlotID)
    }

    func slot(id: UUID?) -> ChordPaletteSlot? {
        if let id, let match = slots.first(where: { $0.id == id }) {
            return match
        }
        if let selectedSlotID, let selected = slots.first(where: { $0.id == selectedSlotID }) {
            return selected
        }
        return slots.first
    }

    func slotID(at index: Int) -> UUID? {
        guard slots.indices.contains(index) else { return nil }
        return slots[index].id
    }

    func voicedPitches(slotID: UUID?, inversion: Int) -> [Int] {
        guard let slot = slot(id: slotID),
              let definition = ChordDefinition.for(id: slot.chordID)
        else {
            return []
        }
        var pitches = definition.intervals
            .map { min(max(slot.root + $0, 0), 127) }
            .sorted()
        guard !pitches.isEmpty else { return [] }

        if inversion > 0 {
            for _ in 0..<inversion {
                guard let first = pitches.first else { break }
                pitches.removeFirst()
                pitches.append(min(first + 12, 127))
                pitches.sort()
            }
        } else if inversion < 0 {
            for _ in 0..<abs(inversion) {
                guard let last = pitches.last else { break }
                pitches.removeLast()
                pitches.insert(max(last - 12, 0), at: 0)
                pitches.sort()
            }
        }

        return pitches
    }

    static func pitchName(for midiNote: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pitchClass = ((midiNote % 12) + 12) % 12
        let octave = midiNote / 12 - 1
        return "\(names[pitchClass])\(octave)"
    }
}
