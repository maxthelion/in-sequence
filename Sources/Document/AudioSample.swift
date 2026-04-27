import Foundation

struct AudioSample: Equatable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let fileRef: AudioFileRef
    let category: AudioSampleCategory
    let lengthSeconds: Double?
    let lengthFrames: Int64?
    let sampleRate: Double?

    init(
        id: UUID,
        name: String,
        fileRef: AudioFileRef,
        category: AudioSampleCategory,
        lengthSeconds: Double?,
        lengthFrames: Int64? = nil,
        sampleRate: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.fileRef = fileRef
        self.category = category
        self.lengthSeconds = lengthSeconds
        self.lengthFrames = lengthFrames
        self.sampleRate = sampleRate
    }
}
