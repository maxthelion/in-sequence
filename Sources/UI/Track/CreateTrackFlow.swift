import SwiftUI

/// One step of the consolidated track-creation flow. The flow presents as a
/// SINGLE continuously-presented sheet (`TracksMatrixView` holds one
/// `.sheet(item:)`); picking Slice / Drum Group / Mono / Poly swaps the step
/// inside the same `StudioModal` instead of dismissing one sheet and
/// re-presenting another (the old double-modal flash).
enum CreateTrackFlowStep: Equatable, Identifiable {
    /// The type-picker grid (Mono / Poly / Slice / Input / Drum Group).
    case pickType
    /// The at-creation sound step for a Mono or Poly track: Blank / Sampler /
    /// pick an AU instrument (the fast path).
    case monoPolySound(TrackType)
    /// The slice-track loop picker (breaks + recordings feed the slicer).
    case sliceSound
    /// The drum-group builder (sounds first, patterns, routing).
    case drumGroupSound

    var id: String {
        switch self {
        case .pickType:
            return "pick-type"
        case .monoPolySound(let trackType):
            return "mono-poly-sound-\(trackType.rawValue)"
        case .sliceSound:
            return "slice-sound"
        case .drumGroupSound:
            return "drum-group-sound"
        }
    }

    /// What a capture-harness command does to the flow sheet.
    enum VisualCommandAction: Equatable {
        case present(CreateTrackFlowStep)
        case close
    }

    /// Capture-harness mapping: the command-file vocabulary drives the flow to
    /// a target step (`create-track-modal:open` → type picker, etc.) or closes
    /// it. `nil` means the command is not a creation-flow command.
    static func action(forVisualCommand command: String) -> VisualCommandAction? {
        switch command {
        case "create-track-modal:open":
            return .present(.pickType)
        case "add-drum-group-modal:open":
            return .present(.drumGroupSound)
        case "add-slice-track-modal:open":
            return .present(.sliceSound)
        case "track-sound-modal:open":
            return .present(.monoPolySound(.monoMelodic))
        case "create-track-modal:close",
             "add-drum-group-modal:close",
             "add-slice-track-modal:close",
             "track-sound-modal:close":
            return .close
        default:
            return nil
        }
    }
}

/// The consolidated "Create Track" modal: one `StudioModal` whose content is
/// switched by `CreateTrackFlowStep` (the same @State-switched-content shape
/// `DrumKitTemplateChooserSheet` uses). Mono/Poly get the same at-creation
/// sound step Drum Group and Slice already had — Blank stays available, a
/// library sample seeds the sampler, and the AU instrument list commits on a
/// single click (bug 20260610-100343 grammar).
struct CreateTrackFlow: View {
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    let initialStep: CreateTrackFlowStep
    let onOpenTrack: () -> Void
    let onDismiss: () -> Void

    @State private var step: CreateTrackFlowStep

    init(
        initialStep: CreateTrackFlowStep,
        onOpenTrack: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.initialStep = initialStep
        self.onOpenTrack = onOpenTrack
        self.onDismiss = onDismiss
        _step = State(initialValue: initialStep)
    }

    private var sampleLibrary: AudioSampleLibrary { .shared }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    }

    /// Live AU instrument list, deduplicated — same source and sanitisation as
    /// `AddDestinationSheet`.
    private var audioInstrumentChoices: [AudioInstrumentChoice] {
        AudioInstrumentChoice.deduplicated(engineController.availableAudioInstruments)
    }

    private var pooledSampleIDs: Set<UUID> {
        Set(session.store.assetPool.filter { $0.kind == .sample }.map(\.assetID))
    }

    private var pooledKitIDs: Set<UUID> {
        Set(session.store.assetPool.filter { $0.kind == .drumKit }.map(\.assetID))
    }

    var body: some View {
        StudioModal(
            title: title,
            subtitle: subtitle,
            showsTitleRule: false,
            minWidth: minWidth,
            minHeight: minHeight,
            onClose: onDismiss,
            headerAccessory: { backButton }
        ) {
            switch step {
            case .pickType:
                pickTypeStep
            case .monoPolySound(let trackType):
                monoPolySoundStep(trackType)
            case .sliceSound:
                AddSliceTrackContent(
                    library: sampleLibrary,
                    sampleEngine: engineController.sampleEngineSink,
                    pooledSampleIDs: pooledSampleIDs,
                    onCreate: { sample in
                        _ = session.appendSliceTrack(sample: sample)
                        finish()
                    }
                )
            case .drumGroupSound:
                AddDrumGroupContent(
                    auInstruments: engineController.availableAudioInstruments,
                    pooledKitIDs: pooledKitIDs,
                    onCreate: { plan in
                        _ = session.addDrumGroup(plan: plan)
                        finish()
                    }
                )
            }
        }
        // The flow is ONE continuously-presented sheet: when the presenting
        // item changes step while the sheet is already up (capture-harness
        // mutual-exclusion commands, e.g. add-slice-track-modal:open while the
        // drum-group step is showing), SwiftUI reuses this view — @State only
        // seeds from initialStep at first mount, so without this the old step
        // stayed mounted and capture rows 02e/02f rendered 02d's modal.
        .onChange(of: initialStep) { _, newStep in
            step = newStep
        }
    }

    // MARK: - Chrome per step

    private var title: String {
        switch step {
        case .pickType:
            return "Create Track"
        case .monoPolySound(let trackType):
            return trackType == .polyMelodic ? "New Poly Track" : "New Mono Track"
        case .sliceSound:
            return "New Slice Track"
        case .drumGroupSound:
            return "Add Drum Group"
        }
    }

    private var subtitle: String? {
        switch step {
        case .pickType:
            return nil
        case .monoPolySound:
            return nil
        case .sliceSound:
            return nil
        case .drumGroupSound:
            return nil
        }
    }

    private var minWidth: CGFloat {
        switch step {
        case .pickType, .monoPolySound:
            return 560
        case .sliceSound:
            return 700
        case .drumGroupSound:
            return 700
        }
    }

    private var minHeight: CGFloat? {
        switch step {
        case .pickType, .monoPolySound:
            return nil
        case .sliceSound:
            return 480
        case .drumGroupSound:
            return 600
        }
    }

    /// Steps entered from the type picker carry a back affordance in the
    /// modal header, next to the ✕ — the flow never dismiss/re-presents.
    @ViewBuilder
    private var backButton: some View {
        if step != .pickType {
            StudioCircleIconButton(
                systemName: "chevron.left",
                size: StudioMetrics.ControlSize.close,
                help: "Back to track types"
            ) {
                step = .pickType
            }
        }
    }

    // MARK: - Step 1: type picker

    private var pickTypeStep: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            createButton(title: "Mono", accent: StudioTheme.cyan, help: "Single melodic lane") {
                step = .monoPolySound(.monoMelodic)
            }
            createButton(title: "Poly", accent: StudioTheme.amber, help: "Chord-capable lane") {
                step = .monoPolySound(.polyMelodic)
            }
            createButton(title: "Slice", accent: StudioTheme.violet, help: "Sample/slice trigger lane") {
                step = .sliceSound
            }
            createButton(
                title: "Input",
                accent: StudioTheme.success,
                help: "Audio input lane",
                isEnabled: session.canAppendAudioInputTrack,
                disabledHelp: "One audio input track is available in this version"
            ) {
                session.appendTrack(trackType: .audioInput)
                finish()
            }
            createButton(title: "Drum Group", accent: StudioTheme.amber, help: "Grouped drum part tracks") {
                step = .drumGroupSound
            }
        }
    }

    // Canon creep purge (2026-07-02): the type cards carry no subtitle
    // explainers — the lane description lives in the hover help.
    private func createButton(
        title: String,
        accent: Color,
        help: String,
        isEnabled: Bool = true,
        disabledHelp: String = "",
        action: @escaping () -> Void
    ) -> some View {
        StudioOptionButton(
            title: title,
            accent: accent,
            minHeight: 120,
            titleFontSize: 21,
            horizontalAlignment: .center,
            contentAlignment: .center,
            centersText: true,
            isEnabled: isEnabled,
            disabledHelp: disabledHelp,
            help: help,
            action: action
        )
    }

    // MARK: - Step 2 (Mono/Poly): sound setup

    /// The "multiple ways to set up a track with a sound" step, modeled on the
    /// drum-part sound chooser (`expandedSoundChooserPanel`): Blank keeps
    /// today's create-then-configure behaviour, Sampler seeds the sample
    /// engine with the first library sample, and the AU instrument rows are
    /// the fast path — one click attaches the AU and opens the track.
    private func monoPolySoundStep(_ trackType: TrackType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            auInstrumentSectionHeader

            if audioInstrumentChoices.isEmpty {
                StudioEmptyListRow(message: "No AU instruments found")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // Rows commit on a single click (bug 20260610-100343):
                        // create the track, attach the AU, open the track.
                        ForEach(audioInstrumentChoices, id: \.id) { choice in
                            StudioOptionButton(title: choice.displayName, accent: StudioTheme.cyan) {
                                createTrackWithAUInstrument(choice, trackType: trackType)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            StudioOptionButton(
                title: "Sampler",
                accent: StudioTheme.violet,
                isEnabled: defaultSampleDestination != nil,
                disabledHelp: "The sample library is empty",
                help: "Use the sample engine with the first library sample"
            ) {
                guard let destination = defaultSampleDestination else { return }
                _ = session.appendTrack(trackType: trackType, soundDestination: destination)
                finish()
            }

            StudioOptionButton(
                title: "Leave Blank",
                accent: StudioTheme.amber,
                help: "Create the track without a sound destination"
            ) {
                session.appendTrack(trackType: trackType)
                finish()
            }
        }
    }

    private var auInstrumentSectionHeader: some View {
        HStack(spacing: 10) {
            Text("AU INSTRUMENTS")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            Text(engineController.audioPluginChoiceScanState.displayText)
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                engineController.rescanAudioPluginChoices()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .studioText(.labelBold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(StudioTheme.violet)
            .disabled(engineController.audioPluginChoiceScanState.isScanning)
            .opacity(engineController.audioPluginChoiceScanState.isScanning ? 0.5 : 1)
        }
    }

    /// The first library sample, or nil when the library is empty — the
    /// Sampler option is disabled then. Never falls back to
    /// `.internalSampler` (an unimplemented, silent sound source).
    private var defaultSampleDestination: Destination? {
        sampleLibrary.samples.first.map { .sample(sampleID: $0.id, settings: .default) }
    }

    /// The AU fast path: the ONE shared session seam
    /// (`appendTrack(trackType:auInstrument:preparingAudioUnitWith:)`) does the
    /// session mutation + AU host prime — never a bespoke attach path (Hard
    /// Rule 5 stays inside `.fullEngineApply`).
    private func createTrackWithAUInstrument(_ choice: AudioInstrumentChoice, trackType: TrackType) {
        _ = session.appendTrack(
            trackType: trackType,
            auInstrument: choice,
            preparingAudioUnitWith: engineController
        )
        finish()
    }

    private func finish() {
        onDismiss()
        onOpenTrack()
    }
}
