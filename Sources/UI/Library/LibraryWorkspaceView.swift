import SwiftUI

extension Notification.Name {
    static let libraryWorkspaceVisualCommand = Notification.Name("SequencerAILibraryWorkspaceVisualCommand")
}

/// The Library page: a global asset browser (category list + entries) and the
/// project pool — the subset of global assets this document references.
struct LibraryWorkspaceView: View {
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    var sampleLibrary: AudioSampleLibrary = .shared
    var drumAssetLibrary: DrumAssetLibrary = .shared
    var recordingLibrary: RecordingLibrary = .shared
    /// Navigate to the single-track detail after a create-from-entity action
    /// (mirrors TracksMatrixView's onOpenTrack).
    var onOpenTrack: () -> Void = {}

    @State private var selectedCategory: LibraryCategory = .breaks
    @State private var auditioningEntryID: String?

    private var catalog: LibraryAssetCatalog {
        LibraryAssetCatalog(
            sampleLibrary: sampleLibrary,
            drumAssetLibrary: drumAssetLibrary,
            recordingLibrary: recordingLibrary
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: StudioMetrics.Spacing.loose) {
            globalPanel
                .frame(maxWidth: .infinity, alignment: .topLeading)
            poolPanel
                .frame(width: 320, alignment: .topLeading)
        }
        .padding(StudioMetrics.Spacing.section)
        .onAppear {
            sampleLibrary.reload()
            recordingLibrary.reload()
            drumAssetLibrary.reload()
        }
        .onDisappear {
            stopAudition()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryWorkspaceVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
        }
    }

    // MARK: - Global library

    private var globalPanel: some View {
        StudioPanel(title: "Global Library", accent: StudioTheme.violet) {
            HStack(alignment: .top, spacing: StudioMetrics.Spacing.roomy) {
                categoryList
                    .frame(width: 190)

                entryList
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var categoryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.hairline) {
                ForEach(LibraryAssetCatalog.categories) { category in
                    categoryRow(category)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 560)
    }

    /// Entry count per category. AU instruments and generators are not
    /// catalog-resolved (no pool semantics), so their counts come straight
    /// from the live component scan / project pool.
    private func entryCount(for category: LibraryCategory) -> Int {
        switch category {
        case .auInstruments:
            return auInstrumentChoices.count
        case .generators:
            return session.store.generatorPool.count
        default:
            return catalog.entryCount(in: category)
        }
    }

    /// Live AU instrument list, deduplicated — same source and sanitisation
    /// as AddDestinationSheet / CreateTrackFlow.
    private var auInstrumentChoices: [AudioInstrumentChoice] {
        AudioInstrumentChoice.deduplicated(engineController.availableAudioInstruments)
    }

    private func categoryRow(_ category: LibraryCategory) -> some View {
        let isSelected = selectedCategory == category
        let count = entryCount(for: category)
        // Empty categories recede so the eye lands on real content (ux-canon
        // rule 11); they stay selectable, just dimmed.
        let isEmpty = count == 0
        let dimmedMuted = StudioTheme.mutedText.opacity(StudioOpacity.inheritedContent)

        return Button {
            selectCategory(category)
        } label: {
            HStack(spacing: StudioMetrics.Spacing.snug) {
                Text(category.displayName)
                    .studioText(isSelected ? .labelBold : .label)
                    .foregroundStyle(isSelected ? StudioTheme.text : (isEmpty ? dimmedMuted : StudioTheme.mutedText))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(count)")
                    .studioText(.micro)
                    .foregroundStyle(isSelected ? StudioTheme.violet : (isEmpty ? dimmedMuted : StudioTheme.mutedText))
            }
            .padding(.horizontal, StudioMetrics.Spacing.compact)
            .padding(.vertical, StudioMetrics.Spacing.tight)
            // Colour identifies, it never floods (ux-canon rule 12): the
            // selected row takes the neutral step; the violet count chip and
            // bold label carry the selection.
            .background(
                isSelected ? Color.white.opacity(StudioOpacity.subtleFill) : Color.clear,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .stroke(isSelected ? StudioTheme.violet : Color.clear, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Category \(category.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var entryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.tight) {
                switch selectedCategory {
                case .auInstruments:
                    auInstrumentList
                case .generators:
                    generatorList
                default:
                    pooledAssetList
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 560)
    }

    @ViewBuilder
    private var pooledAssetList: some View {
        let entries = catalog.entries(in: selectedCategory)
        if entries.isEmpty {
            StudioEmptyListRow(message: "Empty")
        } else {
            ForEach(entries) { entry in
                globalEntryRow(entry)
            }
        }
    }

    /// AU instruments have no pool / audition / missing-asset semantics, so
    /// they get their own row variant: name + facts and a single Create Track
    /// action (the row IS the creation seed).
    @ViewBuilder
    private var auInstrumentList: some View {
        StudioPluginRescanHeader()
        if auInstrumentChoices.isEmpty {
            StudioEmptyListRow(message: "No AU instruments found")
        } else {
            ForEach(auInstrumentChoices, id: \.id) { choice in
                creationSeedRow(
                    name: choice.name,
                    facts: choice.manufacturerName.isEmpty ? "AU instrument" : choice.manufacturerName,
                    createHelp: "Create a track hosting this AU instrument"
                ) {
                    createTrack(fromAUInstrument: choice)
                }
            }
        }
    }

    /// Generators are project-pool state (already "in the project" by
    /// definition) — no pool toggle, just the Create Track action.
    @ViewBuilder
    private var generatorList: some View {
        let generators = session.store.generatorPool
        if generators.isEmpty {
            StudioEmptyListRow(message: "Empty")
        } else {
            ForEach(generators) { generator in
                creationSeedRow(
                    name: generator.name,
                    facts: "\(generator.kind.label) · \(generator.trackType.label)",
                    createHelp: "Create a \(generator.trackType.label) track driven by this generator"
                ) {
                    createTrack(fromGenerator: generator)
                }
            }
        }
    }

    /// Row for entries that only seed track creation (AU instruments,
    /// generators): same chrome as `globalEntryRow`, minus pool/audition.
    private func creationSeedRow(
        name: String,
        facts: String,
        createHelp: String,
        onCreate: @escaping () -> Void
    ) -> some View {
        HStack(spacing: StudioMetrics.Spacing.comfortable) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(facts)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            StudioCircleIconButton(
                systemName: "plus",
                size: StudioMetrics.ControlSize.small,
                accent: StudioTheme.cyan,
                help: createHelp,
                action: onCreate
            )
        }
        .padding(StudioMetrics.Spacing.compact)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func globalEntryRow(_ entry: LibraryEntryPresentation) -> some View {
        let isPooled = session.isAssetPooled(kind: entry.poolKind, assetID: entry.assetID)
        let isAuditioning = auditioningEntryID == entry.id

        return HStack(spacing: StudioMetrics.Spacing.comfortable) {
            Button {
                toggleAudition(entry)
            } label: {
                HStack(spacing: StudioMetrics.Spacing.compact) {
                    if entry.auditionURL != nil {
                        Image(systemName: isAuditioning ? "stop.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isAuditioning ? StudioTheme.violet : StudioTheme.mutedText)
                            .frame(width: 14)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .studioText(.bodyBold)
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(entry.facts)
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.mutedText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.auditionURL == nil)
            .help(entry.auditionURL == nil ? "" : (isAuditioning ? "Stop audition" : "Audition"))

            if isPooled {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    Text("IN PROJECT")
                        .studioText(.microEmphasis)
                        .tracking(0.6)
                }
                .foregroundStyle(StudioTheme.success)
            }

            // Create-track affordance for entries that can seed a track
            // directly (a break -> slice track, a kit -> drum group). The
            // accented circle marks the primary creation action; the plain
            // one stays the pool toggle.
            if let createHelp = createTrackHelp {
                StudioCircleIconButton(
                    systemName: "plus",
                    size: StudioMetrics.ControlSize.small,
                    accent: StudioTheme.cyan,
                    help: createHelp
                ) {
                    createTrack(from: entry)
                }
            }

            StudioCircleIconButton(
                systemName: isPooled ? "minus" : "plus",
                size: StudioMetrics.ControlSize.small,
                help: isPooled ? "Remove from project" : "Add to project"
            ) {
                togglePool(entry)
            }
        }
        .padding(StudioMetrics.Spacing.compact)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(
                    isPooled ? StudioTheme.success.opacity(StudioOpacity.softStroke) : StudioTheme.border,
                    lineWidth: StudioMetrics.borderWidth
                )
        )
    }

    // MARK: - Project pool

    private var poolPanel: some View {
        let resolved = catalog.resolveAll(session.store.assetPool)
        let grouped = PooledAssetKind.allCases.compactMap { kind -> (PooledAssetKind, [LibraryPoolEntryPresentation])? in
            let entries = resolved.filter { $0.ref.kind == kind }
            return entries.isEmpty ? nil : (kind, entries)
        }

        return StudioPanel(title: "Project Pool", accent: StudioTheme.cyan) {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioMetrics.Spacing.comfortable) {
                    if grouped.isEmpty {
                        StudioEmptyListRow(message: "Empty")
                    } else {
                        ForEach(grouped, id: \.0) { kind, entries in
                            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.tight) {
                                StudioSectionHeader(title: kind.displayName, showsBackground: false)
                                ForEach(entries) { entry in
                                    poolEntryRow(entry)
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 560)
        }
    }

    private func poolEntryRow(_ entry: LibraryPoolEntryPresentation) -> some View {
        HStack(spacing: StudioMetrics.Spacing.compact) {
            Button {
                reveal(entry)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: StudioMetrics.Spacing.tight) {
                        Text(entry.name)
                            .studioText(.bodyBold)
                            .foregroundStyle(entry.isMissing ? StudioTheme.mutedText : StudioTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if entry.isMissing {
                            Text("MISSING")
                                .studioText(.microEmphasis)
                                .tracking(0.6)
                                .foregroundStyle(StudioTheme.amber)
                        }
                    }

                    if !entry.facts.isEmpty {
                        Text(entry.facts)
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.mutedText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.revealCategory == nil)
            .help(entry.revealCategory == nil ? "" : "Show in global library")

            StudioCircleIconButton(
                systemName: "xmark",
                size: StudioMetrics.ControlSize.small,
                help: "Remove from project — keeps the global asset"
            ) {
                session.removeAssetFromPool(kind: entry.ref.kind, assetID: entry.ref.assetID)
            }
        }
        .padding(StudioMetrics.Spacing.compact)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(
                    entry.isMissing ? StudioTheme.amber.opacity(StudioOpacity.softStroke) : StudioTheme.border,
                    lineWidth: StudioMetrics.borderWidth
                )
        )
    }

    // MARK: - Create track from entity

    /// Help text for the create-track affordance on the CURRENT category's
    /// pooled-asset rows; nil hides the button. Breaks seed a slice track and
    /// kits seed a drum group; templates/step-order-maps only make sense
    /// applied to an existing track, so they carry no creation action.
    private var createTrackHelp: String? {
        switch selectedCategory {
        case .breaks:
            return "Create a slice track from this break"
        case .drumKits:
            return "Create a drum group from this kit"
        default:
            return nil
        }
    }

    /// Dispatch per-category to the SAME session mutations the Tracks page's
    /// creation flow uses — the Library page is an additional entry point,
    /// not a new creation pipeline.
    private func createTrack(from entry: LibraryEntryPresentation) {
        switch selectedCategory {
        case .breaks:
            guard let sample = sampleLibrary.sample(id: entry.assetID) else { return }
            stopAudition()
            _ = session.appendSliceTrack(sample: sample)
            onOpenTrack()
        case .drumKits:
            guard let kit = drumAssetLibrary.kit(id: entry.assetID) else { return }
            stopAudition()
            // One-click create with the plan defaults (dedicated bus, no
            // template, no shared destination) — parity with the break row.
            _ = session.addDrumGroup(plan: .from(kit: kit))
            onOpenTrack()
        default:
            break
        }
    }

    /// AU fast path: same composition as CreateTrackFlow's AU rows — attach
    /// through setEditedDestination (.fullEngineApply keeps the AU host
    /// teardown/build on the safe path), then prime the host.
    private func createTrack(fromAUInstrument choice: AudioInstrumentChoice) {
        stopAudition()
        let newTrackID = session.appendTrack(
            trackType: .monoMelodic,
            soundDestination: .auInstrument(componentID: choice.audioComponentID, stateBlob: nil)
        )
        if let newTrackID {
            engineController.prepareAudioUnit(for: newTrackID)
        }
        onOpenTrack()
    }

    private func createTrack(fromGenerator generator: GeneratorPoolEntry) {
        stopAudition()
        _ = session.appendTrack(generator: generator)
        onOpenTrack()
    }

    // MARK: - Actions

    private func selectCategory(_ category: LibraryCategory) {
        stopAudition()
        selectedCategory = category
    }

    private func togglePool(_ entry: LibraryEntryPresentation) {
        if session.isAssetPooled(kind: entry.poolKind, assetID: entry.assetID) {
            session.removeAssetFromPool(kind: entry.poolKind, assetID: entry.assetID)
        } else {
            session.addAssetToPool(kind: entry.poolKind, assetID: entry.assetID)
        }
    }

    private func toggleAudition(_ entry: LibraryEntryPresentation) {
        guard let url = entry.auditionURL else { return }
        if auditioningEntryID == entry.id {
            stopAudition()
            return
        }
        engineController.sampleEngineSink.stopAudition()
        engineController.sampleEngineSink.audition(sampleURL: url)
        auditioningEntryID = entry.id
    }

    private func stopAudition() {
        guard auditioningEntryID != nil else { return }
        engineController.sampleEngineSink.stopAudition()
        auditioningEntryID = nil
    }

    private func reveal(_ entry: LibraryPoolEntryPresentation) {
        guard let category = entry.revealCategory else { return }
        selectCategory(category)
    }

    private func applyVisualCommand(_ command: String) {
        if command.hasPrefix("category:"),
           let raw = command.split(separator: ":").last,
           let category = LibraryCategory(rawValue: String(raw)) {
            selectCategory(category)
        }
        if command == "reload" {
            sampleLibrary.reload()
            recordingLibrary.reload()
            drumAssetLibrary.reload()
        }
    }
}
