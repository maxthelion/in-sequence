import SwiftUI

/// Drum-group creation content, ordered sounds first, patterns second. Hosted
/// as a STEP inside `CreateTrackFlow`'s single `StudioModal` (title/subtitle
/// come from the flow's chrome — this view renders no modal wrapper of its
/// own; closing is the flow's ✕):
///
/// 1. **Sounds** — pick a kit from the global pool (factory + user kits), which
///    populates the parts list. Parts stay editable after kit selection:
///    rename, add/remove, swap a part's sound from its tag's category pool.
///    "Blank" remains available as "no kit" — an empty parts list.
/// 2. **Patterns** — optionally choose a global pattern template; the chooser
///    previews the tag intersection with the current parts. None = blank
///    patterns. Template application happens at creation through the same
///    path as the kit matrix's Apply Template action.
/// 3. **Routing** — unchanged: optional shared destination, per-member
///    routes-to-shared.
struct AddDrumGroupContent: View {
    let auInstruments: [AudioInstrumentChoice]
    /// Project-pool kit IDs — pooled kits list before global ones.
    var pooledKitIDs: Set<UUID> = []
    let onCreate: (DrumGroupPlan) -> Void

    @State private var selectedKitID: UUID?
    @State private var plan = DrumGroupPlan(name: "Drum Group", color: "#8AA", members: [])
    @State private var isPresentingDestinationPicker = false
    @State private var destinationPickerDidCommit = false
    @State private var destinationPickerTrigger: DestinationPickerTrigger = .initial

    private enum DestinationPickerTrigger {
        case initial
        case repick
    }

    private var assetLibrary: DrumAssetLibrary { .shared }
    private var sampleLibrary: AudioSampleLibrary { .shared }

    /// Pooled kits first (pool membership is what creation flows offer
    /// first), then the remaining global kits in library order.
    private var orderedKits: [DrumKit] {
        let kits = assetLibrary.kits
        return kits.filter { pooledKitIDs.contains($0.id) } + kits.filter { !pooledKitIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.Spacing.standard) {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioMetrics.Spacing.roomy) {
                    soundsSection
                    patternsSection
                    routingSection
                }
            }
            .scrollIndicators(.never)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // MARK: - Step 1: Sounds

    private var soundsSection: some View {
        StudioPanel(
            title: "Sounds",
            eyebrow: soundsEyebrow,
            accent: StudioTheme.cyan
        ) {
            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.comfortable) {
                kitPickerRow

                VStack(alignment: .leading, spacing: StudioMetrics.Spacing.snug) {
                    ForEach(plan.members.indices, id: \.self) { index in
                        partRow(at: index)
                    }

                    if plan.members.isEmpty {
                        Text("No parts yet")
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                            .padding(.vertical, 4)
                            .help("Pick a kit or add parts one by one")
                    }

                    Button {
                        appendBlankPart()
                    } label: {
                        Label("Add part", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var soundsEyebrow: String {
        "Step 1 — \(plan.members.count) part\(plan.members.count == 1 ? "" : "s"), editable after kit pick"
    }

    private var kitPickerRow: some View {
        HStack(spacing: StudioMetrics.Spacing.snug) {
            Text("KIT")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            kitChip(title: "Blank", isSelected: selectedKitID == nil) {
                applyKit(nil)
            }

            ForEach(orderedKits) { kit in
                kitChip(title: kit.name, isSelected: selectedKitID == kit.id) {
                    applyKit(kit)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func kitChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.mutedText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? StudioTheme.cyan : Color.white.opacity(StudioOpacity.subtleFill),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : StudioTheme.border,
                            lineWidth: StudioMetrics.borderWidth
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kit \(title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func partRow(at index: Int) -> some View {
        HStack(spacing: StudioMetrics.Spacing.comfortable) {
            TextField(
                "Part name",
                text: Binding(
                    get: { plan.members[safeIndex: index]?.trackName ?? "" },
                    set: { newValue in
                        guard plan.members.indices.contains(index) else { return }
                        plan.members[index].trackName = newValue
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)

            tagMenu(at: index)

            soundMenu(at: index)

            if plan.sharedDestination != nil {
                Toggle(
                    "Routes to shared",
                    isOn: Binding(
                        get: { plan.members[safeIndex: index]?.routesToShared ?? false },
                        set: { newValue in
                            guard plan.members.indices.contains(index) else { return }
                            plan.members[index].routesToShared = newValue
                        }
                    )
                )
                .toggleStyle(.checkbox)
            }

            Spacer(minLength: 0)

            Button {
                guard plan.members.indices.contains(index) else { return }
                plan.members.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Remove part")
        }
        .padding(.vertical, 2)
    }

    private func tagMenu(at index: Int) -> some View {
        let currentTag = plan.members[safeIndex: index]?.tag ?? "kick"

        return Menu {
            ForEach(Self.canonicalTags, id: \.self) { tag in
                Button(PatternTemplateApplicationPreview.tagLabel(tag)) {
                    guard plan.members.indices.contains(index) else { return }
                    plan.members[index].tag = tag
                    // Sound pools are per-tag; a tag change invalidates the pick.
                    plan.members[index].sampleID = nil
                }
            }
        } label: {
            menuLabel(PatternTemplateApplicationPreview.tagLabel(currentTag))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 130)
        .help("Part tag — the join key for kits, templates, and sound pools")
    }

    private func soundMenu(at index: Int) -> some View {
        let member = plan.members[safeIndex: index]
        let category = member.flatMap { AudioSampleCategory(voiceTag: $0.tag) }
        let pool = category.map { sampleLibrary.samples(in: $0) } ?? []

        return Menu {
            Button(defaultSoundLabel(category: category)) {
                guard plan.members.indices.contains(index) else { return }
                plan.members[index].sampleID = nil
            }
            ForEach(pool) { sample in
                Button(sample.name) {
                    guard plan.members.indices.contains(index) else { return }
                    plan.members[index].sampleID = sample.id
                }
            }
        } label: {
            menuLabel(soundLabel(for: member, category: category))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 190)
        .disabled(pool.isEmpty)
        .help(pool.isEmpty ? "No sample pool for this tag — the part is created without a destination" : "Swap this part's sound from its tag's pool")
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .studioText(.label)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(StudioTheme.mutedText)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func soundLabel(for member: DrumGroupPlan.Member?, category: AudioSampleCategory?) -> String {
        guard let member else { return "—" }
        if let sampleID = member.sampleID,
           let sample = sampleLibrary.sample(id: sampleID) {
            return sample.name
        }
        return defaultSoundLabel(category: category)
    }

    private func defaultSoundLabel(category: AudioSampleCategory?) -> String {
        if let category, let first = sampleLibrary.firstSample(in: category) {
            return "Default — \(first.name)"
        }
        return "No pool for tag"
    }

    // MARK: - Step 2: Patterns

    private var patternsSection: some View {
        StudioPanel(
            title: "Patterns",
            eyebrow: "Step 2 — optional template, applied into pattern slot 1",
            accent: StudioTheme.violet
        ) {
            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.snug) {
                HStack(spacing: StudioMetrics.Spacing.snug) {
                    Text("TEMPLATE")
                        .studioText(.eyebrow)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)

                    templateChip(title: "None", isSelected: plan.templateID == nil) {
                        plan.templateID = nil
                    }

                    ForEach(assetLibrary.templates) { template in
                        templateChip(title: template.name, isSelected: plan.templateID == template.id) {
                            plan.templateID = template.id
                        }
                    }

                    Spacer(minLength: 0)
                }

                Text(templatePreviewText)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func templateChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.mutedText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? StudioTheme.violet : Color.white.opacity(StudioOpacity.subtleFill),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : StudioTheme.border,
                            lineWidth: StudioMetrics.borderWidth
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Template \(title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var templatePreviewText: String {
        guard let templateID = plan.templateID,
              let template = assetLibrary.template(id: templateID)
        else {
            return "No template — parts start with blank patterns."
        }
        guard !plan.members.isEmpty else {
            return "Add parts to see which the template fills."
        }
        let preview = PatternTemplateApplicationPreview(
            template: template,
            parts: plan.members.map { (tag: $0.tag, name: $0.trackName) }
        )
        return preview.summary
    }

    // MARK: - Step 3: Routing

    private var routingSection: some View {
        StudioPanel(
            title: "Routing",
            eyebrow: "Step 3 — output bus and optional shared destination",
            accent: StudioTheme.success
        ) {
            VStack(alignment: .leading, spacing: 12) {
                busRoutingPicker

                Divider().overlay(StudioTheme.border)

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

    /// Output-bus routing for the group. A new drum group routes to its own
    /// dedicated bus (named after the group) by default; Master is offered as a
    /// non-default alternative.
    private var busRoutingPicker: some View {
        let newBusTitle = "New bus: \(busNamePreview)"
        let isDedicated = plan.busRouting == .dedicatedBus

        return VStack(alignment: .leading, spacing: StudioMetrics.Spacing.snug) {
            HStack(spacing: StudioMetrics.Spacing.snug) {
                Text("OUTPUT")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                busRoutingChip(title: newBusTitle, isSelected: isDedicated) {
                    plan.busRouting = .dedicatedBus
                }

                busRoutingChip(title: "Master", isSelected: !isDedicated) {
                    plan.busRouting = .master
                }

                Spacer(minLength: 0)
            }

            Text(isDedicated
                ? "Recommended — the kit gets its own mixer bus you can process as one unit."
                : "Parts route straight to Master.")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The name the dedicated bus will take — the group name, falling back to a
    /// stable label when the user has cleared it.
    private var busNamePreview: String {
        let trimmed = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Drum Group" : trimmed
    }

    private func busRoutingChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.mutedText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? StudioTheme.success : Color.white.opacity(StudioOpacity.subtleFill),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : StudioTheme.border,
                            lineWidth: StudioMetrics.borderWidth
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Output \(title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
        .padding(StudioMetrics.Spacing.compact)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Create Group") {
                onCreate(plan)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.success)
            .disabled(plan.members.isEmpty)
        }
    }

    // MARK: - Actions

    private func handleDestinationSheetDismiss() {
        guard !destinationPickerDidCommit else {
            return
        }
        if destinationPickerTrigger == .initial {
            plan.sharedDestination = nil
        }
    }

    /// Apply a kit pick: populate the parts list from the kit's parts (tag,
    /// name, sound), preserving routing choices. `nil` = Blank, an empty
    /// parts list. Parts remain fully editable afterwards.
    private func applyKit(_ kit: DrumKit?) {
        selectedKitID = kit?.id
        let preservedSharedDestination = plan.sharedDestination
        let preservedTemplateID = plan.templateID
        let preservedBusRouting = plan.busRouting

        if let kit {
            plan = DrumGroupPlan.from(kit: kit, templateID: preservedTemplateID)
        } else {
            plan = DrumGroupPlan(
                name: "Drum Group",
                color: "#8AA",
                members: [],
                templateID: preservedTemplateID
            )
        }
        plan.sharedDestination = preservedSharedDestination
        plan.busRouting = preservedBusRouting
    }

    private func appendBlankPart() {
        let nextIndex = plan.members.count + 1
        plan.members.append(
            DrumGroupPlan.Member(
                tag: "kick",
                trackName: "Part \(nextIndex)"
            )
        )
    }

    /// Canonical tag list — `DrumKitNoteMap.table`'s keys, sorted for a
    /// stable menu order.
    private static let canonicalTags: [VoiceTag] = DrumKitNoteMap.table.keys.sorted()
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
