import SwiftUI

/// Shared FX insert-chain building blocks used by the three insert-chain
/// surfaces (per-track FX, kit-bus FX, scenes/master-bus FX). These were
/// previously reimplemented near-verbatim in `TrackFXChainView`,
/// `KitBusFXChainView`, and `ScenesWorkspaceView`. The views are intentionally
/// value-in / closure-out: each call site owns its own model (`TrackFXInsert` /
/// `MixerBusInsert` / `MasterBusInsert`) and mutation wiring (session APIs), and
/// passes the resolved presentation values + callbacks here.

// MARK: - Insert row

/// One insert row: drag handle + accent icon well + name/subtitle + bypass
/// switch + remove (✕), drawn on a `subtleFill` tile with a selection stroke.
///
/// The three call sites differ only in small, deliberate ways which are exposed
/// as parameters so the rendered output stays pixel-identical to each surface's
/// prior bespoke implementation:
///   - `iconSize` / `iconWell` / `iconCornerRadius`: the track row uses an 11pt
///     glyph in a 22×22 `.badge`-radius well; kit + scenes use 12pt in a 24×24
///     `.chip`-radius well.
///   - `nameField`: scenes makes the name an editable `TextField`; track + kit
///     show static text. When `nameBinding` is nil the row renders static text.
///   - `showsSelection`: the track chain has no selectable rows, so its stroke
///     is always the neutral border; kit + scenes show a cyan stroke when
///     selected.
struct InsertChainRow: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accent: Color
    let isSelected: Bool
    let isBypassed: Bool

    /// Editable-name binding (scenes). When nil the title is rendered as static
    /// text (track + kit).
    let nameBinding: Binding<String>?

    let iconSize: CGFloat
    let iconWell: CGFloat
    let iconCornerRadius: CGFloat
    let showsSelection: Bool

    let onSelect: (() -> Void)?
    let onToggleBypass: (Bool) -> Void
    let onRemove: () -> Void

    init(
        title: String,
        subtitle: String,
        iconName: String,
        accent: Color,
        isSelected: Bool = false,
        isBypassed: Bool,
        nameBinding: Binding<String>? = nil,
        iconSize: CGFloat,
        iconWell: CGFloat,
        iconCornerRadius: CGFloat,
        showsSelection: Bool,
        onSelect: (() -> Void)? = nil,
        onToggleBypass: @escaping (Bool) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.accent = accent
        self.isSelected = isSelected
        self.isBypassed = isBypassed
        self.nameBinding = nameBinding
        self.iconSize = iconSize
        self.iconWell = iconWell
        self.iconCornerRadius = iconCornerRadius
        self.showsSelection = showsSelection
        self.onSelect = onSelect
        self.onToggleBypass = onToggleBypass
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 10) {
            // Drag handle (reorder by handle, never up/down arrows).
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 18)
                .accessibilityLabel("Reorder \(title)")

            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(StudioTheme.background)
                .frame(width: iconWell, height: iconWell)
                .background(accent, in: RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                if let nameBinding {
                    TextField("FX Name", text: nameBinding)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                } else {
                    Text(title)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Bypass toggle (no "Enabled" text label). The switch reads "on" as
            // active (not bypassed) so the green tint means "processing".
            Toggle("Bypass \(title)", isOn: bypassBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(StudioTheme.success)

            // The circled-✕ is the standard remove component (canon Rule 6 —
            // a bare ✕ where the circled form exists is a finding, 05b/05d).
            StudioCircleIconButton(
                systemName: "xmark",
                size: StudioMetrics.ControlSize.small,
                help: "Remove \(title)",
                action: onRemove
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        // Colour identifies, it never floods (ux-canon rule 12): selection reads
        // from the accent outline, not a tinted row fill.
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(strokeColor, lineWidth: StudioMetrics.borderWidth)
        )
        .opacity(isBypassed ? 0.55 : 1)
        .modifier(SelectableRowModifier(isEnabled: showsSelection, onSelect: onSelect))
    }

    private var strokeColor: Color {
        if showsSelection, isSelected {
            return StudioTheme.cyan
        }
        return StudioTheme.border
    }

    private var bypassBinding: Binding<Bool> {
        Binding(
            get: { !isBypassed },
            set: { isActive in onToggleBypass(!isActive) }
        )
    }
}

/// Adds the tap-to-select content-shape + gesture only for selectable surfaces
/// (kit + scenes). The track chain has no selection, so for it this is a no-op
/// — preserving its exact prior behaviour (no `contentShape`/tap).
private struct SelectableRowModifier: ViewModifier {
    let isEnabled: Bool
    let onSelect: (() -> Void)?

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                .onTapGesture { onSelect?() }
        } else {
            content
        }
    }
}

// MARK: - Native insert parameter editor

/// The per-insert parameter editor for the native insert kinds: the filter
/// editor (Low/High/Band/Notch/Peak segmented control + `SceneFilterCurveView`
/// + Cutoff/Resonance rotary knobs) and the bitcrusher editor (bits stepper +
/// rate/drive sliders). Value-in / closure-out: the call site provides the
/// current settings + per-parameter change closures.
enum NativeInsertParameterEditor {
    // MARK: Filter

    /// Filter editor: Low/High/Band/Notch/Peak segmented control + response
    /// curve + Cutoff/Resonance radial knobs (no wet/dry).
    struct Filter: View {
        let settings: MasterFilterSettings
        /// The accent used by the curve + Cutoff knob + selected mode chip.
        let accent: Color
        let onModeChange: (MasterFilterSettings.Mode) -> Void
        let onCutoffChange: (Double) -> Void
        let onResonanceChange: (Double) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                // Custom studio segmented control: flat, rounded, accent-filled
                // selection (replaces the Aqua `.segmented` Picker).
                modeSegmentedControl

                SceneFilterCurveView(
                    mode: settings.mode,
                    cutoffHz: settings.cutoffHz,
                    resonance: settings.resonance,
                    accent: accent
                )
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .background(StudioTheme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )

                HStack(alignment: .top, spacing: 28) {
                    StudioRotaryKnob(
                        title: "Cutoff",
                        value: settings.cutoffHz,
                        range: 20...20_000,
                        accent: accent,
                        size: 58,
                        format: { "\(Int($0.rounded())) Hz" },
                        onChange: onCutoffChange,
                        onLiveChange: onCutoffChange
                    )
                    // Same accent as Cutoff — mixed ring accents on one
                    // surface were a finding (design review 05b).
                    StudioRotaryKnob(
                        title: "Resonance",
                        value: settings.resonance,
                        range: 0...1,
                        accent: accent,
                        size: 58,
                        format: { String(format: "%.2f", $0) },
                        onChange: onResonanceChange,
                        onLiveChange: onResonanceChange
                    )
                    Spacer(minLength: 0)
                }
            }
        }

        private var modeSegmentedControl: some View {
            HStack(spacing: 4) {
                ForEach(MasterFilterSettings.Mode.allCases, id: \.self) { mode in
                    modeChip(mode)
                }
            }
            .padding(3)
            .background(
                Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
            )
        }

        private func modeChip(_ mode: MasterFilterSettings.Mode) -> some View {
            let isSelected = settings.mode == mode
            return Button {
                onModeChange(mode)
            } label: {
                Text(mode.displayName)
                    .studioText(.labelBold)
                    .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .padding(.horizontal, 10)
                    .background(
                        isSelected ? accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter type \(mode.displayName)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
        }
    }

    // MARK: Bitcrusher

    /// Bitcrusher editor: Bits/Rate/Drive as themed rotary knobs — continuous
    /// values are rotaries, never system slider thumbs or stock steppers
    /// (canon Rule 6, design review 05d). All rings carry the one surface
    /// accent. Emits raw new values; the call site applies them through its
    /// model.
    struct Bitcrusher: View {
        let settings: MasterBitcrusherSettings
        /// The one chrome accent of the hosting surface.
        let accent: Color
        let onBitDepthChange: (Int) -> Void
        let onRateChange: (Double) -> Void
        let onDriveChange: (Double) -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 28) {
                StudioRotaryKnob(
                    title: "Bits",
                    value: Double(settings.bitDepth),
                    range: 4...16,
                    accent: accent,
                    size: 58
                ) { value in
                    onBitDepthChange(Int(value.rounded()))
                }

                StudioRotaryKnob(
                    title: "Rate",
                    value: settings.sampleRateScale,
                    range: 0.05...1,
                    accent: accent,
                    size: 58,
                    format: { "\(Int(($0 * 100).rounded()))%" },
                    onChange: onRateChange,
                    onLiveChange: onRateChange
                )

                StudioRotaryKnob(
                    title: "Drive",
                    value: settings.drive,
                    range: 0...1,
                    accent: accent,
                    size: 58,
                    format: { "\(Int(($0 * 100).rounded()))%" },
                    onChange: onDriveChange,
                    onLiveChange: onDriveChange
                )

                Spacer(minLength: 0)
            }
        }
    }
}
