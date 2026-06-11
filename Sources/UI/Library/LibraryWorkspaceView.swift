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

    private func categoryRow(_ category: LibraryCategory) -> some View {
        let isSelected = selectedCategory == category
        let count = catalog.entryCount(in: category)

        return Button {
            selectCategory(category)
        } label: {
            HStack(spacing: StudioMetrics.Spacing.snug) {
                Text(category.displayName)
                    .studioText(isSelected ? .labelBold : .label)
                    .foregroundStyle(isSelected ? StudioTheme.text : StudioTheme.mutedText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(count)")
                    .studioText(.micro)
                    .foregroundStyle(isSelected ? StudioTheme.violet : StudioTheme.mutedText)
            }
            .padding(.horizontal, StudioMetrics.Spacing.compact)
            .padding(.vertical, StudioMetrics.Spacing.tight)
            .background(
                isSelected ? StudioTheme.violet.opacity(StudioOpacity.selectedFill) : Color.clear,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Category \(category.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var entryList: some View {
        let entries = catalog.entries(in: selectedCategory)

        return ScrollView {
            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.tight) {
                if entries.isEmpty {
                    StudioEmptyListRow(message: "Empty")
                } else {
                    ForEach(entries) { entry in
                        globalEntryRow(entry)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 560)
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
                    lineWidth: 1
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
                    lineWidth: 1
                )
        )
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
