import AVFoundation
import SwiftUI

struct SlicerWaveformWindow: View {
    let sample: AudioSample
    let library: AudioSampleLibrary
    let onCommit: (SliceSet) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SliceSet
    @State private var selectedMarkerID: UUID?

    init(
        sliceSet: SliceSet,
        sample: AudioSample,
        library: AudioSampleLibrary,
        onCommit: @escaping (SliceSet) -> Void
    ) {
        self.sample = sample
        self.library = library
        self.onCommit = onCommit
        _draft = State(initialValue: sliceSet)
        _selectedMarkerID = State(initialValue: sliceSet.markers.dropFirst().first?.id ?? sliceSet.markers.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample.name)
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                    Text("\(sample.category.displayName) • \(max(0, draft.markers.count - 1)) slices")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                Button("Done") {
                    commit()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)
            }

            SlicerWaveformView(
                buckets: waveformBuckets,
                sliceSet: draft,
                sampleLengthFrames: sampleLengthFrames,
                selectedMarkerID: selectedMarkerID,
                onBoundaryMove: moveBoundary(markerID:to:)
            )
            .frame(height: 180)
            .padding(StudioMetrics.Spacing.comfortable)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )

            HStack(alignment: .top, spacing: 14) {
                sliceList
                    .frame(width: 220)

                if let selection = selectedMarkerBinding {
                    SliceInspectorView(
                        markerIndex: selection.index,
                        marker: selection.binding,
                        sampleLengthFrames: sampleLengthFrames
                    )
                    .onChange(of: draft) { _, _ in
                        normalizeAndCommit()
                    }
                } else {
                    StudioPlaceholderTile(title: "No Slice Selected", accent: StudioTheme.cyan)
                        .help("Select a slice marker to edit its range and playback options.")
                }
            }
        }
        .padding(StudioMetrics.Spacing.page)
        .frame(minWidth: 760, minHeight: 520)
        .background(StudioTheme.stageFill)
        .onDisappear {
            commit()
        }
    }

    private var sliceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SLICES")
                .studioText(.eyebrow)
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(draft.markers.enumerated()), id: \.element.id) { index, marker in
                        Button {
                            selectedMarkerID = marker.id
                        } label: {
                            HStack {
                                Text(index == 0 ? "All" : "\(index)")
                                    .studioText(.labelBold)
                                    .foregroundStyle(StudioTheme.text)
                                Spacer()
                                Text("\(marker.startFrame)-\(marker.endFrame)")
                                    .studioText(.label)
                                    .foregroundStyle(StudioTheme.mutedText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(9)
                            // Colour identifies, it never floods (ux-canon
                            // rule 12): the selected row stays neutral; the
                            // cyan lives in its outline.
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                    .stroke(marker.id == selectedMarkerID ? StudioTheme.cyan : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var selectedMarkerBinding: (index: Int, binding: Binding<SliceMarker>)? {
        guard let selectedMarkerID,
              let index = draft.markers.firstIndex(where: { $0.id == selectedMarkerID })
        else {
            return nil
        }
        return (
            index,
            Binding(
                get: { draft.markers[index] },
                set: { draft.markers[index] = $0 }
            )
        )
    }

    private var waveformBuckets: [Float] {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot) else {
            return Array(repeating: 0, count: 160)
        }
        return WaveformDownsampler.downsample(url: url, bucketCount: 160)
    }

    private var sampleLengthFrames: Int64 {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return draft.markers.first?.endFrame ?? 0
        }
        return file.length
    }

    private func moveBoundary(markerID: UUID, to frame: Int64) {
        SliceBoundaryEditing.moveSharedBoundary(
            markerID: markerID,
            to: frame,
            in: &draft,
            sampleLengthFrames: sampleLengthFrames
        )
        selectedMarkerID = markerID
        normalizeAndCommit()
    }

    private func normalizeAndCommit() {
        draft.normalize(sampleLengthFrames: sampleLengthFrames)
        commit()
    }

    private func commit() {
        var normalized = draft
        normalized.normalize(sampleLengthFrames: sampleLengthFrames)
        onCommit(normalized)
    }
}
