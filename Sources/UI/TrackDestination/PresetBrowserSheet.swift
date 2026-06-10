import SwiftUI

struct PresetBrowserSheet: View {
    let auDisplayName: String
    @StateObject private var viewModel: PresetBrowserSheetViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var pollTask: Task<Void, Never>?

    init(
        auDisplayName: String,
        viewModel: PresetBrowserSheetViewModel
    ) {
        self.auDisplayName = auDisplayName
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        StudioModal(
            title: "Presets",
            subtitle: auDisplayName,
            minWidth: 480,
            minHeight: 520,
            onClose: { dismiss() }
        ) {
            searchField

            if viewModel.isReady {
                listBody
            } else {
                loadingPlaceholder
            }

            if let error = viewModel.lastLoadError {
                errorToast(error)
            }
        }
        .onAppear {
            viewModel.reloadAsync()
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
        .onChange(of: viewModel.isReady) { _, isReady in
            guard isReady else {
                return
            }
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(StudioTheme.mutedText)
            TextField("Filter presets", text: $viewModel.filter)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if viewModel.filteredFactory.isEmpty {
                        emptySectionText(viewModel.factory.isEmpty ? "No factory presets" : "No matches")
                    } else {
                        ForEach(viewModel.filteredFactory) { descriptor in
                            AUPresetRowView(
                                descriptor: descriptor,
                                isLoaded: viewModel.loadedID == descriptor.id
                            ) {
                                viewModel.load(descriptor)
                            }
                        }
                    }
                } header: {
                    sectionHeader("Factory")
                }

                Section {
                    if viewModel.filteredUser.isEmpty {
                        emptySectionText(viewModel.user.isEmpty ? "No user presets" : "No matches")
                    } else {
                        ForEach(viewModel.filteredUser) { descriptor in
                            AUPresetRowView(
                                descriptor: descriptor,
                                isLoaded: viewModel.loadedID == descriptor.id
                            ) {
                                viewModel.load(descriptor)
                            }
                        }
                    }
                } header: {
                    sectionHeader("User")
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .studioText(.eyebrow)
            .tracking(0.8)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioTheme.background)
    }

    private func emptySectionText(_ message: String) -> some View {
        Text(message)
            .studioText(.label)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.vertical, 8)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(pollTask == nil ? "Presets unavailable." : "Loading plugin…")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorToast(_ error: PresetLoadingError) -> some View {
        Text(message(for: error))
            .studioText(.label)
            .foregroundStyle(StudioTheme.amber)
            .padding(10)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
    }

    private func message(for error: PresetLoadingError) -> String {
        switch error {
        case .presetNotFound:
            return "Preset no longer exists. Try another."
        case .loadFailed:
            return "Failed to capture AU state. Check the log for details."
        }
    }

    private func startPolling() {
        // Guard against re-entrancy: if a live (uncancelled) task already exists, don't
        // spawn a duplicate. Rapid .onAppear re-fires (e.g. sheet presented inside a
        // NavigationStack transition) would otherwise fan out concurrent polling tasks
        // where only the last one gets cancelled on .onDisappear.
        if let existing = pollTask, !existing.isCancelled {
            return
        }
        pollTask = Task { @MainActor in
            let pollInterval = Duration.milliseconds(500)
            let maxAttempts = 10 // 10 × 500 ms = 5 s
            for _ in 0..<maxAttempts {
                try? await Task.sleep(for: pollInterval)
                if Task.isCancelled {
                    return
                }
                viewModel.reloadAsync()
                if viewModel.isReady {
                    pollTask = nil
                    return
                }
            }
            pollTask = nil
        }
    }
}
