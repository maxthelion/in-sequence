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
            ScrollView {
                VStack(alignment: .leading, spacing: StudioMetrics.Spacing.roomy) {
                    soundsSection
                }
            }
            .scrollIndicators(.never)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    ForEach(plan.members.indices, id: \.self) { index in
                        partRow(at: index)
                    }

                    // Themed outline chip — the stock white-filled bordered
                    // button was a Rule 6 finding (design review 02d).
                    Button {
                        appendBlankPart()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Add part")
                                .studioText(.labelBold)
                        }
                        .foregroundStyle(StudioTheme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(StudioTheme.subtleFill, in: Capsule())
                        .overlay(Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .help("Add a blank part")
                    .padding(.top, 4)
                }
            }
        }
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
                        guard plan.members.indices.contains(index) else { return }
                        plan.members[index].trackName = newValue
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)

            tagMenu(at: index)

            soundMenu(at: index)

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

            // Primary action carries the surface accent — success-green is a
            // fenced state colour, not an action fill.
            Button {
                plan.busRouting = .dedicatedBus
                plan.sharedDestination = nil
                onCreate(plan)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .black))
                    Text("Create Group")
                        .studioText(.microEmphasis)
                        .tracking(0.8)
                }
                .foregroundStyle(StudioTheme.background)
                .frame(height: 32)
                .padding(.horizontal, 14)
                .background(Self.surfaceAccent, in: Capsule())
                .overlay(
                    Capsule().stroke(Self.surfaceAccent, lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .help("Create drum group")
            .accessibilityIdentifier("add-drum-group-create")
        }
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
