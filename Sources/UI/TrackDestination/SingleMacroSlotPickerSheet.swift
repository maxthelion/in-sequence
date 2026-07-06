import SwiftUI

struct SingleMacroSlotPickerSheet: View {
    let slotIndex: Int
    let currentBindingAddresses: Set<UInt64>
    let readParameters: () -> [AUParameterDescriptor]?
    let onSelect: (AUParameterDescriptor) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var params: [AUParameterDescriptor]?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        StudioModal(
            title: "Assign Macro \(slotIndex + 1)",
            minWidth: 420,
            minHeight: 480,
            onClose: { dismiss() }
        ) {
            if let params {
                pickerContent(params: params.filter { !currentBindingAddresses.contains($0.address) })
            } else {
                loadingContent
            }
        }
        .onAppear {
            reloadParameters()
            startPollingIfNeeded()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func pickerContent(params: [AUParameterDescriptor]) -> some View {
        let (candidates, rest) = MacroPickerCandidateRanker.rank(params)
        let filteredCandidates = filter(candidates)
        let filteredRest = filter(rest)

        return VStack(alignment: .leading, spacing: 0) {
            StudioSearchBar(placeholder: "Search parameters", text: $searchText)
                .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !filteredCandidates.isEmpty {
                        Section {
                            ForEach(filteredCandidates, id: \.address) { param in
                                paramRow(param)
                            }
                        } header: {
                            StudioSectionHeader(title: "Likely Candidates")
                        }
                    }

                    Section {
                        if filteredCandidates.isEmpty && filteredRest.isEmpty {
                            Text(params.isEmpty ? "No assignable parameters available." : "No parameters match \"\(searchText)\".")
                                .studioText(.body)
                                .foregroundStyle(StudioTheme.mutedText)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(filteredRest, id: \.address) { param in
                                paramRow(param)
                            }
                        }
                    } header: {
                        StudioSectionHeader(title: "All Parameters")
                    }
                }
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Preparing plug-in parameters…")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paramRow(_ param: AUParameterDescriptor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(StudioTheme.transportAccent)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(param.displayName)
                    .studioText(.bodyEmphasis)
                    .foregroundStyle(StudioTheme.text)

                HStack(spacing: 6) {
                    if !param.group.isEmpty {
                        Text(param.group.joined(separator: " › "))
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    if let unit = param.unit {
                        Text("• \(formatRange(param)) \(unit)")
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(param)
            dismiss()
        }
        .padding(.vertical, 8)
    }

    private func formatRange(_ descriptor: AUParameterDescriptor) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = descriptor.maxValue - descriptor.minValue > 10 ? 0 : 2
        let low = formatter.string(from: NSNumber(value: descriptor.minValue)) ?? "\(descriptor.minValue)"
        let high = formatter.string(from: NSNumber(value: descriptor.maxValue)) ?? "\(descriptor.maxValue)"
        return "\(low)-\(high)"
    }

    private func filter(_ params: [AUParameterDescriptor]) -> [AUParameterDescriptor] {
        guard !searchText.isEmpty else {
            return params
        }

        return params.filter { descriptor in
            if descriptor.displayName.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            if descriptor.identifier.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            return descriptor.group.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func reloadParameters() {
        params = readParameters()
        if params != nil {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func startPollingIfNeeded() {
        guard params == nil else {
            return
        }

        if let pollTask, !pollTask.isCancelled {
            return
        }

        pollTask = Task { @MainActor in
            let pollInterval = Duration.milliseconds(300)
            let maxAttempts = 20
            for _ in 0..<maxAttempts {
                try? await Task.sleep(for: pollInterval)
                if Task.isCancelled {
                    return
                }

                reloadParameters()
                if params != nil {
                    return
                }
            }
            pollTask = nil
        }
    }
}
