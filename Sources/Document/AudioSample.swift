import Foundation

struct AudioSample: Equatable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let fileRef: AudioFileRef
    let category: AudioSampleCategory
    let lengthSeconds: Double?
}
