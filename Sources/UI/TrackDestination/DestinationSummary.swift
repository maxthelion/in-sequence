import Foundation

struct DestinationSummary: Equatable {
    let iconName: String
    let typeLabel: String
    let detail: String

    /// Build a summary reading from a `LiveSequencerStore` rather than a `Project`.
    ///
    /// Identical semantics to `make(for:in:trackID:)`; introduced to drop the
    /// `session.project` read in `TrackDestinationEditor`.
    @MainActor
    static func make(for destination: Destination, in store: LiveSequencerStore, trackID: UUID) -> DestinationSummary {
        make(for: destination, groupLookup: { store.group(for: $0) }, trackID: trackID)
    }

    static func make(for destination: Destination, in project: Project, trackID: UUID) -> DestinationSummary {
        make(for: destination, groupLookup: { project.group(for: $0) }, trackID: trackID)
    }

    private static func make(for destination: Destination, groupLookup: (UUID) -> TrackGroup?, trackID: UUID) -> DestinationSummary {
        switch destination {
        case let .midi(port, channel, noteOffset):
            var parts: [String] = [port?.displayName ?? "Unassigned", "ch \(Int(channel) + 1)"]
            if noteOffset != 0 {
                parts.append("\(noteOffset > 0 ? "+" : "")\(noteOffset) st")
            }
            return DestinationSummary(
                iconName: "pianokeys",
                typeLabel: "MIDI",
                detail: parts.joined(separator: " · ")
            )

        case let .auInstrument(componentID, _):
            let displayName = AudioInstrumentChoice.defaultChoices.first(where: { $0.audioComponentID == componentID })?.displayName
                ?? AudioInstrumentChoice(audioComponentID: componentID).displayName
            return DestinationSummary(
                iconName: "waveform",
                typeLabel: "AU Instrument",
                detail: displayName
            )

        case let .internalSampler(_, preset):
            return DestinationSummary(
                iconName: "rectangle.stack",
                typeLabel: "Internal Sampler",
                detail: preset
            )

        case let .sample(sampleID, settings):
            if let sample = AudioSampleLibrary.shared.sample(id: sampleID) {
                let gainSuffix = settings.gain == 0 ? "" : String(format: " · %+.1f dB", settings.gain)
                return DestinationSummary(
                    iconName: "speaker.wave.2",
                    typeLabel: "Sampler",
                    detail: "\(sample.name)\(gainSuffix)"
                )
            }
            return DestinationSummary(
                iconName: "speaker.wave.2",
                typeLabel: "Sampler",
                detail: "Sample not in library"
            )

        case .inheritGroup:
            guard let group = groupLookup(trackID) else {
                return DestinationSummary(
                    iconName: "square.3.layers.3d.down.right",
                    typeLabel: "Inherit Group",
                    detail: "Not in a group"
                )
            }

            let detail: String
            if let sharedDestination = group.sharedDestination {
                detail = "\(group.name) · \(sharedDestination.summary)"
            } else {
                detail = "\(group.name) · no shared destination"
            }

            return DestinationSummary(
                iconName: "square.3.layers.3d.down.right",
                typeLabel: "Inherit Group",
                detail: detail
            )

        case .none:
            return DestinationSummary(iconName: "", typeLabel: "", detail: "")
        }
    }
}
