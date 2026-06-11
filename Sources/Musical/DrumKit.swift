import Foundation

/// A global library asset: a collection of sounds keyed by part tag.
/// Kits carry no patterns and no destination/routing state.
struct DrumKit: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// Ordered parts; order seeds member order at group creation.
    var parts: [Part]

    struct Part: Codable, Equatable, Hashable, Sendable {
        var tag: VoiceTag
        var trackName: String
        /// AudioSampleLibrary stable ID; nil or dangling resolves to the
        /// first sample in the tag's category (`AudioSampleCategory(voiceTag:)`).
        var sampleID: UUID?

        init(tag: VoiceTag, trackName: String, sampleID: UUID? = nil) {
            self.tag = tag
            self.trackName = trackName
            self.sampleID = sampleID
        }
    }

    init(id: UUID, name: String, parts: [Part]) {
        self.id = id
        self.name = name
        self.parts = parts
    }
}
