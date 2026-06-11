import Foundation

/// Tag-intersection preview for applying a `PatternTemplate` to a set of drum
/// parts: which parts the template fills, which template tags have no matching
/// part, which fills would overwrite a non-empty slot, and which members are
/// skipped (generator-backed slot, duplicate tag).
///
/// The matching rules mirror `Project.applyPatternTemplate` exactly so the
/// preview and the apply never disagree. Used by the creation modal's template
/// step and the kit matrix's Apply Template chooser/confirm step.
struct PatternTemplateApplicationPreview: Equatable {
    /// Part names the template will fill, in member order.
    var filledPartNames: [String]
    /// Template tags with no matching part, display-formatted ("Clap").
    var missingTagLabels: [String]
    /// Subset of filled parts whose target slot currently holds a non-empty clip.
    var overwrittenPartNames: [String]
    /// Parts skipped because their target slot is generator-backed.
    var generatorSkippedPartNames: [String]
    /// Parts skipped because an earlier member already consumed their tag.
    var duplicateTagSkippedPartNames: [String]

    var requiresOverwriteConfirmation: Bool {
        !overwrittenPartNames.isEmpty
    }

    /// One-line summary: "Fills Kick, Snare — no Clap entry".
    var summary: String {
        let fills = filledPartNames.isEmpty
            ? "Fills no parts"
            : "Fills \(filledPartNames.joined(separator: ", "))"
        guard !missingTagLabels.isEmpty else {
            return fills
        }
        let entryWord = missingTagLabels.count == 1 ? "entry" : "entries"
        return "\(fills) — no \(missingTagLabels.joined(separator: ", ")) \(entryWord)"
    }

    /// Display label for a voice tag: "hat-closed" → "Hat Closed".
    static func tagLabel(_ tag: VoiceTag) -> String {
        tag.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Preview for the creation flow: parts exist only as (tag, name) pairs,
    /// so there are no slots to overwrite and no generator-backed slots.
    init(template: PatternTemplate, parts: [(tag: VoiceTag, name: String)]) {
        var filled: [String] = []
        var duplicates: [String] = []
        var consumedTags = Set<VoiceTag>()

        for part in parts where template.patterns[part.tag] != nil {
            if consumedTags.insert(part.tag).inserted {
                filled.append(part.name)
            } else {
                duplicates.append(part.name)
            }
        }

        filledPartNames = filled
        missingTagLabels = Self.missingTagLabels(template: template, matchedTags: consumedTags)
        overwrittenPartNames = []
        generatorSkippedPartNames = []
        duplicateTagSkippedPartNames = duplicates
    }

    /// Preview for applying into an existing group's pattern slot. Matching
    /// follows `Project.applyPatternTemplate`: member order, first occurrence
    /// per tag, generator-backed slots skipped.
    init(
        template: PatternTemplate,
        group: TrackGroup,
        tracks: [StepSequenceTrack],
        patternBanks: [TrackPatternBank],
        clipPool: [ClipPoolEntry],
        slotIndex: Int
    ) {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let banksByTrackID = Dictionary(uniqueKeysWithValues: patternBanks.map { ($0.trackID, $0) })
        let clipsByID = Dictionary(uniqueKeysWithValues: clipPool.map { ($0.id, $0) })

        var filled: [String] = []
        var overwritten: [String] = []
        var generatorSkipped: [String] = []
        var duplicates: [String] = []
        var consumedTags = Set<VoiceTag>()

        for memberID in group.memberIDs {
            guard let track = tracksByID[memberID],
                  track.trackType == .monoMelodic,
                  let tag = track.voiceTag,
                  template.patterns[tag] != nil
            else {
                continue
            }
            guard consumedTags.insert(tag).inserted else {
                duplicates.append(track.name)
                continue
            }

            let bank = banksByTrackID[memberID]
                ?? TrackPatternBank.default(
                    for: track,
                    initialClipID: clipPool.first(where: { $0.trackType == track.trackType })?.id
                )
            let slot = bank.slot(at: slotIndex)
            guard slot.sourceRef.mode != .generator else {
                generatorSkipped.append(track.name)
                continue
            }

            filled.append(track.name)
            if let clipID = slot.sourceRef.clipID,
               let clip = clipsByID[clipID],
               !clipIsEmpty(clip.content) {
                overwritten.append(track.name)
            }
        }

        filledPartNames = filled
        missingTagLabels = Self.missingTagLabels(template: template, matchedTags: consumedTags)
        overwrittenPartNames = overwritten
        generatorSkippedPartNames = generatorSkipped
        duplicateTagSkippedPartNames = duplicates
    }

    private static func missingTagLabels(
        template: PatternTemplate,
        matchedTags: Set<VoiceTag>
    ) -> [String] {
        template.patterns.keys
            .filter { !matchedTags.contains($0) }
            .sorted()
            .map(tagLabel)
    }
}
