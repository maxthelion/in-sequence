import SwiftUI

/// The standard FX-insert editor sheet (bug 20260703-093500): clicking an FX
/// entry on a mixer surface (channel/bus strip, master column, send return)
/// opens THIS `StudioModal`, never a bespoke floating mini-panel.
///
/// One sheet grammar for every `MasterBusInsertKind` chain: the insert name +
/// kind summary take the modal's single title/subtitle slot, enable/bypass is
/// the header accessory, the kind-specific parameter editor is the shared
/// `NativeInsertParameterEditor` (the same filter/bitcrusher editors the
/// scenes surface renders), and reorder/remove live in the footer row.
/// Value-in / closure-out like the rest of the insert-chain components: the
/// call site owns its model (`MasterBusInsert` / `SendBusInsert`) and passes
/// resolved values + mutation closures.
struct FXInsertEditorSheet: View {
    let name: String
    let kind: MasterBusInsertKind
    let accent: Color
    let isEnabled: Binding<Bool>
    /// Wet/dry binding for chains that expose one (send returns); nil hides
    /// the row (bus/master inserts).
    var wet: Binding<Double>? = nil
    let canMoveUp: Bool
    let canMoveDown: Bool
    /// Move the insert by the given delta (-1 up, +1 down) in its chain.
    let onMove: (Int) -> Void
    let onRemove: () -> Void
    let onClose: () -> Void
    /// Read-modify-write seam for the kind-specific parameters: the call site
    /// applies the mutation to the CURRENT persisted kind (never a stale
    /// render-time copy).
    let mutateKind: (@escaping (inout MasterBusInsertKind) -> Void) -> Void

    var body: some View {
        StudioModal(
            title: name,
            subtitle: kind.summary,
            accent: accent,
            minWidth: 560,
            onClose: onClose,
            headerAccessory: {
                Toggle("Enabled", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(accent)
                    .help(isEnabled.wrappedValue ? "Bypass insert" : "Enable insert")
            },
            content: {
                VStack(alignment: .leading, spacing: 14) {
                    if let wet {
                        wetRow(wet)
                    }

                    kindEditor

                    Divider()
                        .overlay(StudioTheme.border)

                    footerActions
                }
            }
        )
        .presentationBackground(.clear)
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("fx-insert-editor-sheet")
    }

    // MARK: - Kind-specific parameters

    @ViewBuilder
    private var kindEditor: some View {
        switch kind {
        case let .nativeFilter(settings):
            NativeInsertParameterEditor.Filter(
                settings: settings,
                accent: accent,
                onModeChange: { mode in
                    mutateFilter { $0.mode = mode }
                },
                onCutoffChange: { cutoff in
                    mutateFilter { $0.cutoffHz = cutoff }
                },
                onResonanceChange: { resonance in
                    mutateFilter { $0.resonance = resonance }
                }
            )

        case let .nativeBitcrusher(settings):
            NativeInsertParameterEditor.Bitcrusher(
                settings: settings,
                accent: accent,
                onBitDepthChange: { bitDepth in
                    mutateBitcrusher { $0.bitDepth = bitDepth }
                },
                onRateChange: { rate in
                    mutateBitcrusher { $0.sampleRateScale = rate }
                },
                onDriveChange: { drive in
                    mutateBitcrusher { $0.drive = drive }
                }
            )

        case .auEffect:
            Label("AU Effect", systemImage: "slider.horizontal.3")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private func mutateFilter(_ update: @escaping (inout MasterFilterSettings) -> Void) {
        mutateKind { kind in
            guard case var .nativeFilter(settings) = kind else { return }
            update(&settings)
            kind = .nativeFilter(settings)
        }
    }

    private func mutateBitcrusher(_ update: @escaping (inout MasterBitcrusherSettings) -> Void) {
        mutateKind { kind in
            guard case var .nativeBitcrusher(settings) = kind else { return }
            update(&settings)
            kind = .nativeBitcrusher(settings)
        }
    }

    // MARK: - Wet/dry (send returns only)

    private func wetRow(_ wet: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text("Wet")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 48, alignment: .leading)
            Slider(value: wet, in: 0...1)
                .tint(accent)
            Text("\(Int((wet.wrappedValue * 100).rounded()))%")
                .studioText(.eyebrow)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Reorder + remove

    private var footerActions: some View {
        HStack(spacing: 6) {
            moveButton(systemName: "arrow.up", delta: -1, isEnabled: canMoveUp)
            moveButton(systemName: "arrow.down", delta: 1, isEnabled: canMoveDown)
            Spacer(minLength: 8)
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
                    .studioText(.label)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove insert")
        }
    }

    private func moveButton(systemName: String, delta: Int, isEnabled: Bool) -> some View {
        Button {
            onMove(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(!isEnabled)
        .help(delta < 0 ? "Move insert up" : "Move insert down")
    }
}
