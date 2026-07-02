import SwiftUI

// Kit trigger-routing editor surfaces (AC: drum-group routing). The sheet is
// presented by DrumKitMatrixView; the mode control, row, button style, and the
// shared destination-label helper are private to this file.

private func drumRoutingDestinationLabel(_ destination: Destination) -> String {
    if case let .sample(sampleID, settings) = destination {
        let gainLabel = settings.gain == 0 ? "" : String(format: " • %+.1f dB", settings.gain)
        if let sample = AudioSampleLibrary.shared.sample(id: sampleID) {
            return "\(sample.name)\(gainLabel)"
        }
        return "Sample \(sampleID.uuidString.prefix(4))\(gainLabel)"
    }
    return destination.summary
}

struct DrumGroupRoutingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DrumGroupRoutingEditorDraft
    @State private var isPresentingDestinationPicker = false

    let audioInstrumentChoices: [AudioInstrumentChoice]
    let onApply: (Project.DrumGroupRoutingDraft) -> Void
    let onCancel: () -> Void

    init(
        draft: DrumGroupRoutingEditorDraft,
        audioInstrumentChoices: [AudioInstrumentChoice],
        onApply: @escaping (Project.DrumGroupRoutingDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.audioInstrumentChoices = audioInstrumentChoices
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        StudioModal(
            title: "Edit Routing",
            subtitle: draft.groupName,
            minWidth: 620,
            minHeight: 520,
            onClose: {
                draft.cancel()
                onCancel()
                dismiss()
            }
        ) {
            destinationSection

            DrumGroupRoutingModeControl(selection: $draft.triggerMappingMode)

            warningsAndErrors

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($draft.rows) { $row in
                        DrumGroupRoutingEditorRow(draftMode: draft.triggerMappingMode, row: $row)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 360)

            HStack {
                Spacer()

                Button {
                    guard let projectDraft = draft.projectDraft() else { return }
                    onApply(projectDraft)
                    dismiss()
                } label: {
                    Text("Apply")
                        .studioText(.labelBold)
                }
                .buttonStyle(DrumGroupRoutingEditorButtonStyle(accent: StudioTheme.success, isProminent: true))
                .disabled(!draft.canApply)
            }
        }
        .sheet(isPresented: $isPresentingDestinationPicker) {
            AddDestinationSheet(
                trackHasGroup: false,
                audioInstrumentChoices: audioInstrumentChoices,
                sampleLibrary: .shared,
                onCommit: { destination in
                    draft.sharedDestination = destination
                }
            )
        }
        .onAppear {
            postRoutingEditorVisualState(isVisible: true)
        }
        .onDisappear {
            postRoutingEditorVisualState(isVisible: false)
        }
        .onChange(of: draft) {
            postRoutingEditorVisualState(isVisible: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .drumGroupRoutingEditorVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
        }
    }

    private var destinationSection: some View {
        let storedForGroupedModesOnly = draft.triggerMappingMode == .individual

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Shared Destination")
                        .studioText(.eyebrowBold)
                        .foregroundStyle(StudioTheme.mutedText)

                    if storedForGroupedModesOnly {
                        Text("Stored for grouped modes")
                            .studioText(.eyebrow)
                            .foregroundStyle(StudioTheme.mutedText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Color.white.opacity(StudioOpacity.subtleFill),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                            )
                    }
                }

                Text(draft.sharedDestination.map(drumRoutingDestinationLabel) ?? "No shared destination")
                    .studioText(.body)
                    .foregroundStyle(storedForGroupedModesOnly ? StudioTheme.mutedText : StudioTheme.text)
                    .lineLimit(2)
                    .help(storedForGroupedModesOnly ? "Individual mode uses each part's own destination" : "")
            }

            Spacer()

            Button {
                isPresentingDestinationPicker = true
            } label: {
                Text("Change")
                    .studioText(.labelBold)
            }
            .buttonStyle(DrumGroupRoutingEditorButtonStyle())
            .disabled(storedForGroupedModesOnly)
            .help(storedForGroupedModesOnly ? "Switch to Per Note or Per Channel to edit the stored shared destination." : "Change shared destination")

            if draft.sharedDestination != nil {
                Button {
                    draft.sharedDestination = nil
                } label: {
                    Text("Clear")
                        .studioText(.labelBold)
                }
                .buttonStyle(DrumGroupRoutingEditorButtonStyle())
                .disabled(storedForGroupedModesOnly)
                .help(storedForGroupedModesOnly ? "Switch to Per Note or Per Channel to clear the stored shared destination." : "Clear shared destination")
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(
            Color.white.opacity(storedForGroupedModesOnly ? 0.015 : StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(
                    StudioTheme.border.opacity(storedForGroupedModesOnly ? 0.65 : 1),
                    lineWidth: StudioMetrics.borderWidth
                )
        )
    }

    @ViewBuilder
    private var warningsAndErrors: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(draft.warnings, id: \.message) { warning in
                Text(warning.message)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.amber)
            }

            ForEach(draft.validationIssues.map(Self.validationMessage), id: \.self) { message in
                Text(message)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.amber)
            }
        }
    }

    private static func validationMessage(_ issue: DrumGroupRoutingEditorDraft.ValidationIssue) -> String {
        switch issue {
        case .invalidNote:
            return "One or more note names are invalid."
        case .invalidChannel:
            return "Channels must be 1-16."
        case .impossibleIndividualRouting:
            return "A part needs an own destination before individual mode can apply."
        case .perChannelRequiresMIDISharedDestination:
            return "Per-channel mode requires a MIDI shared destination."
        }
    }

    private func postRoutingEditorVisualState(isVisible: Bool) {
        NotificationCenter.default.post(
            name: .drumGroupRoutingEditorRenderedVisualState,
            object: nil,
            userInfo: [
                "visible": isVisible,
                "mode": isVisible ? draft.triggerMappingMode.rawValue : "none",
                "canApply": isVisible && draft.canApply,
                "sharedDestinationKind": isVisible ? draft.sharedDestination?.kindLabel ?? "none" : "none",
                "warnings": isVisible ? draft.warnings.map(\.message).joined(separator: "|") : "none",
                "validationIssues": isVisible ? draft.validationIssues.map(Self.validationIssueLabel).joined(separator: "|") : "none",
                "rowInheritance": isVisible ? draft.rows.map { $0.inheritsGroupDestination ? "inherit" : "own" }.joined(separator: "|") : "none",
                "noteInputs": isVisible ? draft.rows.map(\.noteInput).joined(separator: "|") : "none",
                "channelInputs": isVisible ? draft.rows.map(\.channelInput).joined(separator: "|") : "none",
            ]
        )
    }

    private static func validationIssueLabel(_ issue: DrumGroupRoutingEditorDraft.ValidationIssue) -> String {
        switch issue {
        case .invalidNote:
            return "invalidNote"
        case .invalidChannel:
            return "invalidChannel"
        case .impossibleIndividualRouting:
            return "impossibleIndividualRouting"
        case .perChannelRequiresMIDISharedDestination:
            return "perChannelRequiresMIDISharedDestination"
        }
    }

    private func applyVisualCommand(_ command: String) {
        switch command {
        case "routing-per-note":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
            draft.setTriggerMappingMode(.perNote)
        case "routing-per-channel":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
            draft.setTriggerMappingMode(.perChannel)
        case "routing-individual":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            draft.setTriggerMappingMode(.individual)
            resetVisualRowInputs()
            for memberID in draft.rows.map(\.memberID) {
                draft.setMemberInheritsGroupDestination(false, memberID: memberID)
            }
        case "routing-duplicate-channel":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            draft.setTriggerMappingMode(.perChannel)
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
            for memberID in draft.rows.prefix(2).map(\.memberID) {
                draft.setChannelInput("10", memberID: memberID)
            }
        case "routing-invalid-note":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            draft.setTriggerMappingMode(.perNote)
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
            if let firstRow = draft.rows.first {
                draft.setNoteInput("C#", memberID: firstRow.memberID)
            }
        case "routing-non-midi":
            draft.sharedDestination = .sample(sampleID: UUID(), settings: .default)
            draft.setTriggerMappingMode(.perChannel)
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
        default:
            break
        }

        postRoutingEditorVisualState(isVisible: true)
    }

    private func setVisualRowsInheritGroupDestination(_ inherits: Bool) {
        for memberID in draft.rows.map(\.memberID) {
            draft.setMemberInheritsGroupDestination(inherits, memberID: memberID)
        }
    }

    private func resetVisualRowInputs() {
        let memberIDs = draft.rows.map(\.memberID)
        for (index, memberID) in memberIDs.enumerated() {
            draft.setNoteInput("C2", memberID: memberID)
            draft.setChannelInput("\(min(index + 1, 16))", memberID: memberID)
        }
    }
}

private struct DrumGroupRoutingModeControl: View {
    @Binding var selection: DrumTriggerMappingMode

    private let modes: [(title: String, mode: DrumTriggerMappingMode)] = [
        ("Per Note", .perNote),
        ("Per Channel", .perChannel),
        ("Individual", .individual),
    ]

    var body: some View {
        StudioSegmentedControl(
            title: "Mode",
            selection: $selection,
            segments: modes.map { option in
                StudioSegment(
                    title: option.title,
                    value: option.mode,
                    accessibilityLabel: "Routing mode \(option.title)"
                )
            },
            accent: StudioTheme.cyan,
            layout: StudioSegmentedControl.Layout(minHeight: 30, horizontalPadding: 10)
        )
    }
}

private struct DrumGroupRoutingEditorButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var accent: Color = StudioTheme.cyan
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                backgroundFill(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .stroke(borderColor, lineWidth: StudioMetrics.borderWidth)
            )
            .opacity(isEnabled ? 1 : 0.48)
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isProminent {
            return accent.opacity(isPressed ? StudioOpacity.accentStroke : StudioOpacity.selectedFill)
        }
        return Color.white.opacity(isPressed ? StudioOpacity.mutedFill : StudioOpacity.subtleFill)
    }

    private var borderColor: Color {
        if isProminent {
            return accent.opacity(isEnabled ? 0.72 : StudioOpacity.softStroke)
        }
        return StudioTheme.border.opacity(isEnabled ? 0.9 : 0.65)
    }
}

private struct DrumGroupRoutingEditorRow: View {
    let draftMode: DrumTriggerMappingMode
    @Binding var row: DrumGroupRoutingEditorDraft.MemberRow

    private var mappingControlsDisabled: Bool {
        row.mappingControlsDisabled(in: draftMode)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                Text(row.inheritsGroupDestination ? "Inherits group" : (row.ownDestination.map(drumRoutingDestinationLabel) ?? "Own destination required"))
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
            .frame(width: 210, alignment: .leading)

            if draftMode != .individual {
                Toggle(isOn: $row.inheritsGroupDestination) {
                    Text("Inherit")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                    .toggleStyle(.switch)
                    .frame(width: 86)
            } else {
                Text("Own")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
                    .frame(width: 86)
            }

            if draftMode == .perNote {
                TextField("C2", text: $row.noteInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 82)
                    .disabled(mappingControlsDisabled)
            } else if draftMode == .perChannel {
                TextField("1", text: $row.channelInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .disabled(mappingControlsDisabled)
            } else {
                Text("Mappings disabled")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer()
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }
}
