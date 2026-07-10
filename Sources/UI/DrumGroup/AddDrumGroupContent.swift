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
/// 2. Pattern templates live on the kit page after creation. New kits always
///    start on their dedicated kit bus in this compact creation flow.
struct AddDrumGroupContent: View {
    let auInstruments: [AudioInstrumentChoice]
    /// Project-pool kit IDs — pooled kits list before global ones.
    var pooledKitIDs: Set<UUID> = []
    let onCreate: (DrumGroupPlan) -> Void

    @State private var selectedKitID: UUID?
    @State private var plan = DrumGroupPlan(name: "Drum Group", color: "#8AA", members: [])
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
            soundsSection
            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .tracksMatrixVisualCommand)) { notification in
            guard let command = notification.object as? String,
                  command.hasPrefix("add-drum-group-fixture:")
            else { return }
            applyVisualFixture(String(command.dropFirst("add-drum-group-fixture:".count)))
        }
    }

    // MARK: - Step 1: Sounds

    /// The ONE chrome accent of this modal (drum-group identity — matches its
    /// type card in the create flow). The old cyan/violet/green per-section
    /// roulette broke one-accent-per-surface, and green additionally misused
    /// a fenced state colour as a selection fill (design review 02d).
    private static let surfaceAccent = StudioTheme.transportAccent

    // Label purge (canon Rules 1/3, design review 02d): the step-descriptor
    // eyebrows and the "No parts yet" filler are gone — the section titles
    // carry the flow order, the parts list shows the real count, and the
    // instructional sentences live in .help tooltips.
    private var soundsSection: some View {
        StudioPanel(
            title: "Sounds",
            accent: Self.surfaceAccent,
            showsHeader: false
        ) {
            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.comfortable) {
                kitPickerRow

                VStack(alignment: .leading, spacing: StudioMetrics.Spacing.snug) {
                    if !plan.members.isEmpty {
                        StudioCustomVerticalScrollView {
                            LazyVStack(alignment: .leading, spacing: StudioMetrics.Spacing.snug) {
                                ForEach(plan.members.indices, id: \.self) { index in
                                    partRow(at: index)
                                }
                            }
                        }
                        .frame(height: partListHeight)
                    }

                    commandButton(title: "Add Part", isPrimary: false, help: "Add a blank part") {
                        AddDrumGroupPlanEditing.appendBlankPart(to: &plan)
                    }
                }
            }
        }
    }

    private var partListHeight: CGFloat {
        min(CGFloat(plan.members.count) * 64, 320)
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
                    isSelected ? Self.surfaceAccent : StudioTheme.subtleFill,
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
                        AddDrumGroupPlanEditing.renamePart(at: index, to: newValue, in: &plan)
                    }
                )
            )
            .textFieldStyle(.plain)
            .frame(maxWidth: 180)

            tagMenu(at: index)

            soundMenu(at: index)

            Spacer(minLength: 0)

            Button {
                AddDrumGroupPlanEditing.removePart(at: index, from: &plan)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
                    .frame(width: StudioMetrics.ControlSize.small, height: StudioMetrics.ControlSize.small)
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
            }
            .buttonStyle(.plain)
            .help("Remove part")
        }
        .padding(.horizontal, StudioMetrics.Spacing.comfortable)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func tagMenu(at index: Int) -> some View {
        let currentTag = plan.members[safeIndex: index]?.tag ?? "kick"

        return Menu {
            ForEach(Self.canonicalTags, id: \.self) { tag in
                Button(PatternTemplateApplicationPreview.tagLabel(tag)) {
                    AddDrumGroupPlanEditing.retagPart(at: index, as: tag, in: &plan)
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
                AddDrumGroupPlanEditing.selectSample(nil, forPartAt: index, in: &plan)
            }
            ForEach(pool) { sample in
                Button(sample.name) {
                    AddDrumGroupPlanEditing.selectSample(sample.id, forPartAt: index, in: &plan)
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
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
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

    private var footer: some View {
        HStack {
            Spacer()

            commandButton(title: "Create Group", isPrimary: true, help: "Create drum group") {
                onCreate(AddDrumGroupPlanEditing.finalized(plan))
            }
            .accessibilityIdentifier("add-drum-group-create")
        }
    }

    private func commandButton(
        title: String,
        isPrimary: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isPrimary ? StudioTheme.background : StudioTheme.text)
                .frame(minWidth: 112, minHeight: 36)
                .padding(.horizontal, 12)
                .background(
                    isPrimary ? Self.surfaceAccent : StudioTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(isPrimary ? Self.surfaceAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Actions

    /// Apply a kit pick: populate the parts list from the kit's parts (tag,
    /// name, sound), preserving routing choices. `nil` = Blank, an empty
    /// parts list. Parts remain fully editable afterwards.
    private func applyKit(_ kit: DrumKit?) {
        selectedKitID = kit?.id
        let preservedTemplateID = plan.templateID

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
        plan.sharedDestination = nil
        plan.busRouting = .dedicatedBus
    }

    private func applyVisualFixture(_ fixture: String) {
        selectedKitID = nil
        switch fixture {
        case "blank":
            plan = DrumGroupPlan(name: "Drum Group", color: "#8AA", members: [])
        case "populated":
            plan = .blankDefault
        default:
            return
        }
    }

    /// Canonical tag list — `DrumKitNoteMap.table`'s keys, sorted for a
    /// stable menu order.
    private static let canonicalTags: [VoiceTag] = DrumKitNoteMap.table.keys.sorted()
}

enum AddDrumGroupPlanEditing {
    static func appendBlankPart(to plan: inout DrumGroupPlan) {
        plan.members.append(
            DrumGroupPlan.Member(
                tag: "kick",
                trackName: "Part \(plan.members.count + 1)"
            )
        )
    }

    static func renamePart(at index: Int, to name: String, in plan: inout DrumGroupPlan) {
        guard plan.members.indices.contains(index) else { return }
        plan.members[index].trackName = name
    }

    static func retagPart(at index: Int, as tag: VoiceTag, in plan: inout DrumGroupPlan) {
        guard plan.members.indices.contains(index) else { return }
        plan.members[index].tag = tag
        plan.members[index].sampleID = nil
    }

    static func selectSample(_ sampleID: UUID?, forPartAt index: Int, in plan: inout DrumGroupPlan) {
        guard plan.members.indices.contains(index) else { return }
        plan.members[index].sampleID = sampleID
    }

    static func removePart(at index: Int, from plan: inout DrumGroupPlan) {
        guard plan.members.indices.contains(index) else { return }
        plan.members.remove(at: index)
    }

    static func finalized(_ plan: DrumGroupPlan) -> DrumGroupPlan {
        var finalized = plan
        finalized.busRouting = .dedicatedBus
        finalized.sharedDestination = nil
        return finalized
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
