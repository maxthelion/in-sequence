import SwiftUI

/// The slice-track loop picker, hosted as a STEP inside `CreateTrackFlow`'s
/// single `StudioModal` (title/subtitle come from the flow's chrome). Breaks
/// and recordings both feed the slicer; pooled loops list first.
struct AddSliceTrackContent: View {
    let library: AudioSampleLibrary
    let sampleEngine: SamplePlaybackSink
    /// Project-pool sample IDs — pooled loops list first.
    var pooledSampleIDs: Set<UUID> = []
    let onCreate: (AudioSample) -> Void

    @State private var previewingSampleID: UUID?

    /// Breaks and recordings both feed the slicer; pooled loops on top,
    /// then global, each name-sorted.
    private var samples: [AudioSample] {
        let loops = library.samples(in: .breaks) + library.samples(in: .recordings)
        return loops.sorted { lhs, rhs in
            let lhsPooled = pooledSampleIDs.contains(lhs.id)
            let rhsPooled = pooledSampleIDs.contains(rhs.id)
            if lhsPooled != rhsPooled {
                return lhsPooled
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var breaksFolderPath: String {
        library.libraryRoot.appendingPathComponent("breaks", isDirectory: true).path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if samples.isEmpty {
                StudioPlaceholderTile(
                    title: "No Break Loops Found",
                    accent: StudioTheme.violet
                )
                .help("Add WAV loops to \(breaksFolderPath)")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(samples) { sample in
                            sampleRow(sample)
                        }
                    }
                }
                .frame(maxHeight: 440)
            }
        }
        .onDisappear {
            sampleEngine.stopAudition()
        }
        .onAppear {
            library.reload()
        }
    }

    /// Recording buffers get the amber accent; factory breaks keep violet.
    private func accent(for sample: AudioSample) -> Color {
        sample.category == .recordings ? StudioTheme.amber : StudioTheme.violet
    }

    private func sampleRow(_ sample: AudioSample) -> some View {
        let rowAccent = accent(for: sample)
        let isRecording = sample.category == .recordings
        return HStack(alignment: .center, spacing: 12) {
            // Accent rail distinguishes recordings from factory breaks at a glance.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(rowAccent)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(sample.name)
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Solid status badge (ux-canon rule 12): accent fill with
                    // a dark glyph, never a translucent accent wash.
                    Text(isRecording ? "BUFFER" : "FACTORY")
                        .studioText(.microEmphasis)
                        .tracking(0.6)
                        .foregroundStyle(StudioTheme.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(rowAccent, in: Capsule())

                    if pooledSampleIDs.contains(sample.id) {
                        Text("IN PROJECT")
                            .studioText(.microEmphasis)
                            .tracking(0.6)
                            .foregroundStyle(StudioTheme.success)
                    }
                }

                Text(sampleDetail(sample))
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                togglePreview(sample)
            } label: {
                Image(systemName: previewingSampleID == sample.id ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.background)
                    .frame(width: 28, height: 28)
                    .background(rowAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .help(previewingSampleID == sample.id ? "Stop preview" : "Preview loop")

            Button {
                sampleEngine.stopAudition()
                onCreate(sample)
            } label: {
                Text("Use Loop")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(rowAccent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, StudioMetrics.Spacing.comfortable)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func togglePreview(_ sample: AudioSample) {
        if previewingSampleID == sample.id {
            sampleEngine.stopAudition()
            previewingSampleID = nil
            return
        }

        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot) else {
            return
        }

        sampleEngine.stopAudition()
        sampleEngine.audition(sampleURL: url)
        previewingSampleID = sample.id
    }

    private func sampleDetail(_ sample: AudioSample) -> String {
        let length = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "--"
        let rate = sample.sampleRate.map { String(format: "%.1fk", $0 / 1_000) } ?? "--"
        return "\(sample.category.displayName) • \(length) • \(rate)"
    }
}
