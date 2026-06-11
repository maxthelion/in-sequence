import Foundation

struct DrumGroupPlan: Equatable {
    struct Member: Equatable {
        var tag: VoiceTag
        var trackName: String
        /// Preferred AudioSampleLibrary sample for this part. Nil or dangling
        /// resolves to the first sample in the tag's category at creation.
        var sampleID: UUID?
        var routesToShared: Bool

        init(
            tag: VoiceTag,
            trackName: String,
            sampleID: UUID? = nil,
            routesToShared: Bool = true
        ) {
            self.tag = tag
            self.trackName = trackName
            self.sampleID = sampleID
            self.routesToShared = routesToShared
        }
    }

    var name: String
    var color: String
    var members: [Member]
    /// Optional pattern template applied into pattern slot 0 at creation,
    /// via the same path as post-creation application.
    var templateID: UUID?
    var sharedDestination: Destination?

    init(
        name: String,
        color: String,
        members: [Member],
        templateID: UUID? = nil,
        sharedDestination: Destination? = nil
    ) {
        self.name = name
        self.color = color
        self.members = members
        self.templateID = templateID
        self.sharedDestination = sharedDestination
    }

    static var blankDefault: DrumGroupPlan {
        DrumGroupPlan(
            name: "Drum Group",
            color: "#8AA",
            members: [
                Member(tag: "kick", trackName: "Kick"),
                Member(tag: "snare", trackName: "Snare"),
                Member(tag: "hat-closed", trackName: "Hat"),
                Member(tag: "clap", trackName: "Clap"),
            ],
            templateID: nil,
            sharedDestination: nil
        )
    }

    static func from(kit: DrumKit, templateID: UUID? = nil) -> DrumGroupPlan {
        DrumGroupPlan(
            name: kit.name,
            color: "#8AA",
            members: kit.parts.map { part in
                Member(
                    tag: part.tag,
                    trackName: part.trackName,
                    sampleID: part.sampleID,
                    routesToShared: true
                )
            },
            templateID: templateID,
            sharedDestination: nil
        )
    }
}
