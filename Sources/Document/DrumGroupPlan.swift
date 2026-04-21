import Foundation

struct DrumGroupPlan: Equatable {
    struct Member: Equatable {
        var tag: VoiceTag
        var trackName: String
        var seedPattern: [Bool]
        var routesToShared: Bool

        init(
            tag: VoiceTag,
            trackName: String,
            seedPattern: [Bool],
            routesToShared: Bool = true
        ) {
            self.tag = tag
            self.trackName = trackName
            self.seedPattern = seedPattern
            self.routesToShared = routesToShared
        }
    }

    var name: String
    var color: String
    var members: [Member]
    var prepopulateClips: Bool
    var sharedDestination: Destination?

    static var blankDefault: DrumGroupPlan {
        let emptyPattern = Array(repeating: false, count: 16)
        return DrumGroupPlan(
            name: "Drum Group",
            color: "#8AA",
            members: [
                Member(tag: "kick", trackName: "Kick", seedPattern: emptyPattern),
                Member(tag: "snare", trackName: "Snare", seedPattern: emptyPattern),
                Member(tag: "hat-closed", trackName: "Hat", seedPattern: emptyPattern),
                Member(tag: "clap", trackName: "Clap", seedPattern: emptyPattern),
            ],
            prepopulateClips: false,
            sharedDestination: nil
        )
    }

    static func templated(from preset: DrumKitPreset) -> DrumGroupPlan {
        DrumGroupPlan(
            name: preset.displayName,
            color: preset.suggestedGroupColor,
            members: preset.members.map { presetMember in
                Member(
                    tag: presetMember.tag,
                    trackName: presetMember.trackName,
                    seedPattern: presetMember.seedPattern,
                    routesToShared: true
                )
            },
            prepopulateClips: true,
            sharedDestination: nil
        )
    }
}
