import Foundation

extension Project {
    func preferredCaptureDestinationSlot(for trackID: UUID) -> Int {
        let currentSlot = selectedPatternIndex(for: trackID)
        return (0..<TrackPatternBank.slotCount).first(where: { $0 != currentSlot }) ?? currentSlot
    }

    @discardableResult
    mutating func saveCapturedClip(
        _ content: ClipContent,
        trackID: UUID,
        destinationSlotIndex: Int? = nil,
        name: String? = nil
    ) -> UUID? {
        guard let track = tracks.first(where: { $0.id == trackID }) else {
            return nil
        }

        let clip = ClipPoolEntry(
            id: UUID(),
            name: name ?? "\(track.name) capture",
            trackType: track.trackType,
            content: content.normalized
        )
        clipPool.append(clip)

        let slotIndex = min(
            max(destinationSlotIndex ?? preferredCaptureDestinationSlot(for: trackID), 0),
            TrackPatternBank.slotCount - 1
        )
        setPatternClipID(clip.id, for: trackID, slotIndex: slotIndex)
        return clip.id
    }
}
