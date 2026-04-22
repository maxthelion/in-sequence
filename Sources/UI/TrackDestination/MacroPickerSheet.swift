import SwiftUI

/// Modal picker for selecting AU parameters as macro bindings on a track.
///
/// Shows a "Likely candidates" section (ranked by `MacroPickerCandidateRanker`)
/// and an "All parameters" section. The user multi-selects parameters;
/// on Confirm the diff is applied (add newly checked, remove newly unchecked).
///
/// For internal-device destinations (.internalSampler / .sample), opens in
/// read-only mode showing the built-in macros that are auto-assigned.
struct MacroPickerSheet: View {

    // MARK: - Mode

    enum Mode {
        /// AU instrument — user can pick parameters from parameterTree.
        case auPicker(params: [AUParameterDescriptor])
        /// Internal device — read-only list of built-in macros.
        case builtinReadOnly(bindings: [TrackMacroBinding])
    }

    // MARK: - Inputs

    let mode: Mode
    /// IDs of already-bound parameters/bindings (pre-checked on open).
    let currentBindingAddresses: Set<UInt64>
    let onCommit: (_ added: [AUParameterDescriptor], _ removed: Set<UInt64>) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var searchText = ""
    /// Selected parameter addresses (checked in the picker).
    @State private var selectedAddresses: Set<UInt64> = []

    private let maxBindings = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            switch mode {
            case let .auPicker(params):
                auPickerContent(params: params)
            case let .builtinReadOnly(bindings):
                builtinReadOnlyContent(bindings: bindings)
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .task {
            // Pre-select currently-bound parameters.
            selectedAddresses = currentBindingAddresses
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Macros")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)

                switch mode {
                case .auPicker:
                    Text("\(selectedAddresses.count) of up to \(maxBindings) selected")
                        .studioText(.body)
                        .foregroundStyle(selectedAddresses.count >= maxBindings ? StudioTheme.amber : StudioTheme.mutedText)
                case .builtinReadOnly:
                    Text("Built-in macros for this device are pre-assigned and cannot be removed.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            Spacer()

            if case .builtinReadOnly = mode {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.success)
            } else {
                HStack(spacing: 10) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)

                    Button("Confirm") { commitSelection() }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.success)
                }
            }
        }
    }

    // MARK: - AU Picker Content

    private func auPickerContent(params: [AUParameterDescriptor]) -> some View {
        let (candidates, rest) = MacroPickerCandidateRanker.rank(params)
        let filteredCandidates = filter(candidates)
        let filteredRest = filter(rest)

        return VStack(alignment: .leading, spacing: 0) {
            searchBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !filteredCandidates.isEmpty {
                        Section {
                            ForEach(filteredCandidates, id: \.address) { param in
                                paramRow(param)
                            }
                        } header: {
                            sectionHeader("Likely Candidates")
                        }
                    }

                    Section {
                        if filteredRest.isEmpty && filteredCandidates.isEmpty {
                            Text("No parameters match \"\(searchText)\".")
                                .studioText(.body)
                                .foregroundStyle(StudioTheme.mutedText)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(filteredRest, id: \.address) { param in
                                paramRow(param)
                            }
                        }
                    } header: {
                        sectionHeader("All Parameters")
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(StudioTheme.mutedText)
            TextField("Search parameters", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .studioText(.eyebrow)
            .tracking(0.8)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioTheme.background)
    }

    private func paramRow(_ param: AUParameterDescriptor) -> some View {
        let isSelected = selectedAddresses.contains(param.address)
        let isDisabled = !isSelected && selectedAddresses.count >= maxBindings

        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? StudioTheme.success : StudioTheme.mutedText)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(param.displayName)
                    .studioText(.bodyEmphasis)
                    .foregroundStyle(isDisabled ? StudioTheme.mutedText : StudioTheme.text)

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
            guard !isDisabled || isSelected else { return }
            if isSelected {
                selectedAddresses.remove(param.address)
            } else {
                selectedAddresses.insert(param.address)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(isSelected ? StudioTheme.success.opacity(0.06) : Color.clear)
    }

    // MARK: - Built-in Read-Only Content

    private func builtinReadOnlyContent(bindings: [TrackMacroBinding]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(bindings, id: \.id) { binding in
                    builtinRow(binding)
                }
            }
            .padding(.top, 8)
        }
    }

    private func builtinRow(_ binding: TrackMacroBinding) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(StudioTheme.success)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(binding.displayName)
                    .studioText(.bodyEmphasis)
                    .foregroundStyle(StudioTheme.text)

                Text("Built-in — \(formatBuiltinRange(binding.descriptor))")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func filter(_ params: [AUParameterDescriptor]) -> [AUParameterDescriptor] {
        guard !searchText.isEmpty else { return params }
        let q = searchText.lowercased()
        return params.filter {
            $0.displayName.lowercased().contains(q)
            || $0.group.contains { $0.lowercased().contains(q) }
        }
    }

    private func commitSelection() {
        let previousAddresses = currentBindingAddresses
        let added = auParams.filter { selectedAddresses.contains($0.address) && !previousAddresses.contains($0.address) }
        let removed = previousAddresses.subtracting(selectedAddresses)
        onCommit(added, removed)
        dismiss()
    }

    private var auParams: [AUParameterDescriptor] {
        if case let .auPicker(params) = mode { return params }
        return []
    }

    private func formatRange(_ param: AUParameterDescriptor) -> String {
        let fmt = NumberFormatter()
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 0
        let minStr = fmt.string(from: NSNumber(value: param.minValue)) ?? "\(param.minValue)"
        let maxStr = fmt.string(from: NSNumber(value: param.maxValue)) ?? "\(param.maxValue)"
        return "\(minStr)–\(maxStr)"
    }

    private func formatBuiltinRange(_ descriptor: TrackMacroDescriptor) -> String {
        "\(descriptor.minValue)–\(descriptor.maxValue)"
    }
}
