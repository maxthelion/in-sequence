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
        VStack(alignment: .leading, spacing: 16) {
            header
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
        .padding(20)
        .frame(minWidth: 480, minHeight: 520)
        .background(StudioTheme.background)
        .onAppear {
            viewModel.reload()
            if !viewModel.isReady {
                startPolling()
            }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Presets")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)

                Text(auDisplayName)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
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
        List {
            Section("Factory") {
                if viewModel.filteredFactory.isEmpty {
                    Text(viewModel.factory.isEmpty ? "No factory presets" : "No matches")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
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
            }

            Section("User") {
                if viewModel.filteredUser.isEmpty {
                    Text(viewModel.user.isEmpty ? "No user presets" : "No matches")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
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
            }
        }
        .listStyle(.inset)
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
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            let pollInterval = Duration.milliseconds(500)
            let maxAttempts = 10 // 10 × 500 ms = 5 s
            for _ in 0..<maxAttempts {
                try? await Task.sleep(for: pollInterval)
                if Task.isCancelled {
                    return
                }
                viewModel.reload()
                if viewModel.isReady {
                    pollTask = nil
                    return
                }
            }
            pollTask = nil
        }
    }
}
