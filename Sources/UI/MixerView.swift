import SwiftUI

struct MixerView: View {
    @Binding var document: SeqAIDocument
    var onEditTrack: ((UUID) -> Void)? = nil
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    private var project: Project {
        session.project
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(project.tracks, id: \.id) { track in
                    MixerChannelStrip(
                        track: track,
                        destinationLabel: destinationLabel(for: track),
                        isSelected: track.id == project.selectedTrackID,
                        engineController: engineController,
                        onSelect: {
                            session.mutateProject(impact: .fullEngineApply) { project in
                                project.selectTrack(id: track.id)
                            }
                            onEditTrack?(track.id)
                        },
                        onSetMix: { mix in
                            session.setTrackMix(trackID: track.id, mix: mix)
                        },
                        onToggleMute: {
                            session.mutateProject(impact: .fullEngineApply) { project in
                                guard let index = project.tracks.firstIndex(where: { $0.id == track.id }) else {
                                    return
                                }
                                project.tracks[index].mix.isMuted.toggle()
                            }
                        }
                    )
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func destinationLabel(for track: StepSequenceTrack) -> String {
        if case .inheritGroup = track.destination,
           let group = project.group(for: track.id),
           let sharedDestination = group.sharedDestination
        {
            return sharedDestination.kindLabel
        }
        return track.destination.kindLabel
    }
}

private struct MixerChannelStrip: View {
    let track: StepSequenceTrack
    let destinationLabel: String
    let isSelected: Bool
    let engineController: EngineController
    let onSelect: () -> Void
    let onSetMix: (TrackMixSettings) -> Void
    let onToggleMute: () -> Void

    @StateObject private var levelControl = ThrottledMixValue()
    @StateObject private var panControl = ThrottledMixValue()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                    Text(destinationLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Text("Selected")
                        .studioText(.micro)
                        .tracking(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(StudioTheme.cyan.opacity(StudioOpacity.softFill), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .center, spacing: 8) {
                        VerticalLevelFader(
                            level: displayedLevel,
                            isMuted: track.mix.isMuted,
                            onBegin: { beginLevelDrag() },
                            onChange: { updateLevel($0) },
                            onEnd: { commitLevel() }
                        )
                        .frame(width: 36, height: 150)

                        Text("\(Int((displayedLevel * 100).rounded()))%")
                            .studioText(.eyebrow)
                            .monospacedDigit()
                            .foregroundStyle(StudioTheme.text)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pan")
                            .studioText(.eyebrow)
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.mutedText)

                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { displayedPan },
                                    set: { updatePan($0) }
                                ),
                                in: -1...1,
                                onEditingChanged: handlePanEditingChanged
                            )
                            .tint(StudioTheme.violet)
                            .frame(width: 88)

                            Text(panLabel)
                                .studioText(.eyebrow)
                                .monospacedDigit()
                                .foregroundStyle(StudioTheme.text)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }

            HStack(spacing: 8) {
                Button(track.mix.isMuted ? "Unmute" : "Mute") {
                    onToggleMute()
                }
                .buttonStyle(.borderedProminent)
                .tint(track.mix.isMuted ? StudioTheme.amber : StudioTheme.chrome)

                Button("Edit", action: onSelect)
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.cyan)
            }

            Rectangle()
                .fill(StudioTheme.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                Label("\(track.activeStepCount) active steps", systemImage: "square.grid.2x2")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                Label("\(track.pitches.count) pitches", systemImage: "music.note")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .padding(16)
        .frame(width: 200, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel)
                .fill(StudioTheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel)
                .stroke(isSelected ? StudioTheme.cyan : StudioTheme.border, lineWidth: isSelected ? 2 : 1)
        )
    }

    private var displayedLevel: Double {
        levelControl.rendered(committed: track.mix.clampedLevel)
    }

    private var displayedPan: Double {
        panControl.rendered(committed: track.mix.clampedPan)
    }

    private var panLabel: String {
        let value = displayedPan
        if value < -0.05 {
            return "L\(Int(abs(value) * 100))"
        }
        if value > 0.05 {
            return "R\(Int(value * 100))"
        }
        return "C"
    }

    private func beginLevelDrag() {
        if !levelControl.isDragging {
            levelControl.begin(with: track.mix.clampedLevel)
        }
    }

    private func updateLevel(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        if !levelControl.isDragging {
            levelControl.begin(with: track.mix.clampedLevel)
        }
        guard levelControl.update(clamped) else { return }
        var liveMix = track.mix
        liveMix.level = clamped
        liveMix.pan = displayedPan
        onSetMix(liveMix)
    }

    private func commitLevel() {
        // commit() resets drag state; the final value was already written via updateLevel.
        _ = levelControl.commit()
    }

    private func handlePanEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !panControl.isDragging {
                panControl.begin(with: track.mix.clampedPan)
            }
        } else {
            commitPan()
        }
    }

    private func updatePan(_ pan: Double) {
        let clamped = min(max(pan, -1), 1)
        if !panControl.isDragging {
            panControl.begin(with: track.mix.clampedPan)
        }
        guard panControl.update(clamped) else { return }
        var liveMix = track.mix
        liveMix.level = displayedLevel
        liveMix.pan = clamped
        onSetMix(liveMix)
    }

    private func commitPan() {
        // commit() resets drag state; the final value was already written via updatePan.
        _ = panControl.commit()
    }
}

private struct VerticalLevelFader: View {
    let level: Double
    let isMuted: Bool
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let filledHeight = max(12, height * clampedLevel)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(isMuted ? Color.white.opacity(StudioOpacity.selectedFill) : StudioTheme.cyan)
                    .frame(height: filledHeight)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(StudioOpacity.selectedFill))
                    .frame(width: 16, height: 4)
                    .offset(y: -filledHeight + 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onBegin()
                        let normalized = 1 - min(max(value.location.y / max(height, 1), 0), 1)
                        onChange(normalized)
                    }
                    .onEnded { _ in
                        onEnd()
                    }
            )
        }
    }

    private var clampedLevel: CGFloat {
        CGFloat(min(max(level, 0), 1))
    }
}
