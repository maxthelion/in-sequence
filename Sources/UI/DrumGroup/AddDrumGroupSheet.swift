import SwiftUI

struct AddDrumGroupSheet: View {
    let auInstruments: [AudioInstrumentChoice]
    let onCreate: (DrumGroupPlan) -> Void
    let onCancel: () -> Void

    @State private var mode: Mode = .blank
    @State private var selectedPreset: DrumKitPreset = .kit808
    @State private var plan: DrumGroupPlan = .blankDefault
    @State private var isPresentingDestinationPicker = false
    @State private var destinationPickerDidCommit = false
    @State private var destinationPickerTrigger: DestinationPickerTrigger = .initial

    private enum Mode: Hashable {
        case blank
        case templated
    }

    private enum DestinationPickerTrigger {
        case initial
        case repick
    }

    var body: some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header
                templateSection
                tracksSection
                optionsSection
                Spacer(minLength: 0)
                footer
            }
            .padding(20)
        }
        .frame(minWidth: 680, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StudioTheme.stageFill)
        .presentationBackground(.clear)
        .sheet(
            isPresented: $isPresentingDestinationPicker,
            onDismiss: handleDestinationSheetDismiss
        ) {
            AddDestinationSheet(
                trackHasGroup: false,
                audioInstrumentChoices: auInstruments,
                sampleLibrary: .shared
            ) { destination in
                destinationPickerDidCommit = true
                plan.sharedDestination = destination
            }
            .presentationBackground(.clear)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add Drum Group")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)

            Text("Start blank or from a preset, then optionally attach one shared destination for the group.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private var templateSection: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: $mode) {
                Text("Blank").tag(Mode.blank)
                Text("Templated").tag(Mode.templated)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .onChange(of: mode) { _, newValue in
                applyMode(newValue)
            }

            if mode == .templated {
                Picker("Preset", selection: $selectedPreset) {
                    ForEach(DrumKitPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedPreset) { _, newValue in
                    applyTemplatedPreset(newValue)
                }
            }

            Spacer()
        }
    }

    private var tracksSection: some View {
        StudioPanel(
            title: "Tracks",
            eyebrow: tracksEyebrow,
            accent: StudioTheme.cyan
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.members.indices, id: \.self) { index in
                    trackRow(at: index)
                }

                if mode == .blank {
                    Button {
                        appendBlankRow()
                    } label: {
                        Label("Add track", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var tracksEyebrow: String {
        "\(plan.members.count) track\(plan.members.count == 1 ? "" : "s") — \(mode == .blank ? "editable" : "preset preview")"
    }

    @ViewBuilder
    private func trackRow(at index: Int) -> some View {
        HStack(spacing: 12) {
            if mode == .blank {
                TextField(
                    "Track name",
                    text: Binding(
                        get: { plan.members[index].trackName },
                        set: { plan.members[index].trackName = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            } else {
                Text(plan.members[index].trackName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                    .frame(maxWidth: 220, alignment: .leading)
            }

            Text(plan.members[index].tag)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(maxWidth: 120, alignment: .leading)

            if plan.sharedDestination != nil {
                Toggle(
                    "Routes to shared",
                    isOn: Binding(
                        get: { plan.members[index].routesToShared },
                        set: { plan.members[index].routesToShared = $0 }
                    )
                )
                .toggleStyle(.checkbox)
            }

            Spacer(minLength: 0)

            if mode == .blank {
                Button {
                    plan.members.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .buttonStyle(.plain)
                .disabled(plan.members.count <= 1)
            }
        }
        .padding(.vertical, 4)
    }

    private var optionsSection: some View {
        StudioPanel(
            title: "Options",
            eyebrow: "Seed patterns and shared output",
            accent: StudioTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if mode == .templated {
                    Toggle("Prepopulate step patterns", isOn: $plan.prepopulateClips)
                        .toggleStyle(.checkbox)
                }

                Toggle(
                    "Add shared destination",
                    isOn: Binding(
                        get: { plan.sharedDestination != nil },
                        set: { newValue in
                            if newValue {
                                destinationPickerTrigger = .initial
                                destinationPickerDidCommit = false
                                isPresentingDestinationPicker = true
                            } else {
                                plan.sharedDestination = nil
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)

                if let destination = plan.sharedDestination {
                    destinationSummaryRow(for: destination)
                }
            }
        }
    }

    private func destinationSummaryRow(for destination: Destination) -> some View {
        let summary = DestinationSummary.make(
            for: destination,
            in: .empty,
            trackID: Project.empty.selectedTrackID
        )

        return HStack(spacing: 12) {
            Image(systemName: summary.iconName.isEmpty ? "dot.radiowaves.left.and.right" : summary.iconName)
                .foregroundStyle(StudioTheme.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.typeLabel.isEmpty ? "Destination" : summary.typeLabel)
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text(summary.detail.isEmpty ? destination.summary : summary.detail)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            Button("Pick…") {
                destinationPickerTrigger = .repick
                destinationPickerDidCommit = false
                isPresentingDestinationPicker = true
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)

            Button("Create Group") {
                onCreate(plan)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.success)
            .disabled(plan.members.isEmpty)
        }
    }

    private func handleDestinationSheetDismiss() {
        guard !destinationPickerDidCommit else {
            return
        }
        if destinationPickerTrigger == .initial {
            plan.sharedDestination = nil
        }
    }

    private func applyMode(_ newMode: Mode) {
        let preservedSharedDestination = plan.sharedDestination
        let preservedPrepopulate = plan.prepopulateClips

        switch newMode {
        case .blank:
            plan = .blankDefault
        case .templated:
            plan = .templated(from: selectedPreset)
        }

        plan.sharedDestination = preservedSharedDestination
        plan.prepopulateClips = newMode == .templated ? (preservedPrepopulate || plan.prepopulateClips) : false
    }

    private func applyTemplatedPreset(_ preset: DrumKitPreset) {
        let preservedSharedDestination = plan.sharedDestination
        let preservedPrepopulate = plan.prepopulateClips

        plan = .templated(from: preset)
        plan.sharedDestination = preservedSharedDestination
        plan.prepopulateClips = preservedPrepopulate || plan.prepopulateClips
    }

    private func appendBlankRow() {
        let nextIndex = plan.members.count + 1
        plan.members.append(
            DrumGroupPlan.Member(
                tag: "kick",
                trackName: "Track \(nextIndex)",
                seedPattern: Array(repeating: false, count: 16)
            )
        )
    }
}
