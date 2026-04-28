import Foundation

enum SliceMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case grid
    case transient
    case manual
}

struct SliceSet: Codable, Equatable, Hashable, Sendable, Identifiable {
    static let emptyID = UUID(uuidString: "00000000-0000-4000-8000-000000000510")!
    static let empty = SliceSet(
        id: emptyID,
        sampleID: nil,
        markers: [SliceMarker(id: emptyID, startFrame: 0, endFrame: 0)],
        mode: .manual
    )

    var id: UUID
    var sampleID: UUID?
    var markers: [SliceMarker]
    var mode: SliceMode
    var bpmHint: Double?
    var bars: Double?

    init(
        id: UUID = UUID(),
        sampleID: UUID?,
        markers: [SliceMarker],
        mode: SliceMode = .grid,
        bpmHint: Double? = nil,
        bars: Double? = nil
    ) {
        self.id = id
        self.sampleID = sampleID
        self.markers = markers
        self.mode = mode
        self.bpmHint = bpmHint
        self.bars = bars
    }

    var userSliceCount: Int {
        max(0, markers.count - 1)
    }

    var displaySliceCount: Int {
        markers.count
    }

    mutating func normalize(sampleLengthFrames: Int64) {
        let sampleLength = max(0, sampleLengthFrames)
        let wholeID = markers.first?.id ?? id
        var wholeStart = min(max(markers.first?.startFrame ?? 0, 0), sampleLength)
        var wholeEnd = min(max(markers.first?.endFrame ?? sampleLength, wholeStart), sampleLength)
        if sampleLength > 0, wholeEnd <= wholeStart {
            wholeStart = 0
            wholeEnd = sampleLength
        }
        let wholeSample = SliceMarker(
            id: wholeID,
            startFrame: wholeStart,
            endFrame: wholeEnd,
            gain: markers.first?.clampedGain ?? 0,
            reverse: markers.first?.reverse ?? false,
            microTimingSteps: markers.first?.clampedMicroTimingSteps ?? 0,
            tag: markers.first?.tag ?? ""
        )
        let cropStart = wholeSample.startFrame
        let cropEnd = wholeSample.endFrame

        var seenIDs: Set<UUID> = [wholeSample.id]
        let userMarkers = markers
            .dropFirst()
            .compactMap { marker -> SliceMarker? in
                guard var normalized = marker.normalized(sampleLengthFrames: sampleLength) else {
                    return nil
                }
                normalized.startFrame = min(max(normalized.startFrame, cropStart), cropEnd)
                normalized.endFrame = min(max(normalized.endFrame, normalized.startFrame), cropEnd)
                guard sampleLength == 0 || normalized.endFrame > normalized.startFrame else {
                    return nil
                }
                if seenIDs.contains(normalized.id) {
                    normalized.id = UUID()
                }
                seenIDs.insert(normalized.id)
                return normalized
            }
            .sorted { lhs, rhs in
                if lhs.startFrame == rhs.startFrame {
                    return lhs.endFrame < rhs.endFrame
                }
                return lhs.startFrame < rhs.startFrame
            }

        markers = [wholeSample] + userMarkers
    }

    func marker(at index: Int) -> SliceMarker? {
        guard !markers.isEmpty else {
            return nil
        }
        let clampedIndex = min(max(index, 0), markers.count - 1)
        return markers[clampedIndex]
    }
}
