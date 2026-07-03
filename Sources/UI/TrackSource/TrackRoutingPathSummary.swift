import Foundation

/// One-glance summary of a track's audio path for the ROUTING tab.
///
/// The ROUTING tab re-homes the (previously permanent) destination column into
/// a fourth track-editor tab. Its pill carries this summary so the path is
/// legible without opening the tab: instrument/source → destination, plus the
/// active send levels. This is presentation only — it derives from the same
/// `Destination`, output-bus, and `TrackMixSettings` model the mixer edits; it
/// never introduces new routing semantics.
struct TrackRoutingPathSummary: Equatable {
    /// Short instrument/source label (e.g. "Clap kit", "AU Instrument").
    let instrumentLabel: String
    /// Destination label: a bus name, or "Master".
    let destinationLabel: String
    /// Send A level, 0...1, clamped.
    let sendA: Double
    /// Send B level, 0...1, clamped.
    let sendB: Double
    /// Which master scene crossfade lane this track feeds.
    let sceneMembership: TrackMixSettings.SceneMembership

    /// Whether either send is meaningfully open (mirrors the mixer threshold).
    var hasActiveSend: Bool {
        MixerSendDisplayModel.isNonZero(sendA) || MixerSendDisplayModel.isNonZero(sendB)
    }

    /// Pill label: `INSTRUMENT → DEST`, e.g. "Clap kit → Bus A".
    var pillSummary: String {
        "\(instrumentLabel) → \(destinationLabel)"
    }

    /// Sends caption shown next to the destination, e.g. "sends 35/20".
    /// `nil` when both sends are closed.
    var sendsSummary: String? {
        guard hasActiveSend else { return nil }
        let a = Int((MixerSendDisplayModel.clamped(sendA) * 100).rounded())
        let b = Int((MixerSendDisplayModel.clamped(sendB) * 100).rounded())
        return "sends \(a)/\(b)"
    }

    /// Builds the summary from the resolved destination, output title, and mix.
    ///
    /// - Parameters:
    ///   - destinationSummary: the resolved-instrument summary (reuses
    ///     `DestinationSummary`); its `typeLabel`/`detail` drive the
    ///     instrument label.
    ///   - outputTitle: the destination/bus title (reuses
    ///     `MixerRoutingDisplayModel.outputTitle`).
    ///   - mix: the track's mix settings (for sends).
    static func make(
        destinationSummary: DestinationSummary,
        outputTitle: String,
        mix: TrackMixSettings
    ) -> TrackRoutingPathSummary {
        TrackRoutingPathSummary(
            instrumentLabel: instrumentLabel(from: destinationSummary),
            destinationLabel: outputTitle,
            sendA: MixerSendDisplayModel.clamped(mix.sendA),
            sendB: MixerSendDisplayModel.clamped(mix.sendB),
            sceneMembership: mix.sceneMembership
        )
    }

    /// Prefers the concrete instrument detail (e.g. the AU/sample name) and
    /// falls back to the type label; an unset destination reads "No instrument".
    private static func instrumentLabel(from summary: DestinationSummary) -> String {
        let detail = summary.detail.trimmingCharacters(in: .whitespaces)
        if !detail.isEmpty {
            // The detail can carry extra qualifiers ("· +3 dB", "· ch 1");
            // keep the leading token group up to the first separator so the
            // pill stays one-glance.
            if let head = detail.components(separatedBy: " · ").first, !head.isEmpty {
                return head
            }
            return detail
        }
        let label = summary.typeLabel.trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? "No instrument" : label
    }
}
