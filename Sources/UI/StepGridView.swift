import AppKit
import Foundation
import SwiftUI

enum StepVisualState: Equatable {
    case off
    case on
    case accented
}

struct StepGridView: View {
    let stepStates: [StepVisualState]
    let indexOffset: Int
    let playingStepIndex: Int?
    let selectedStepIndexes: Set<Int>
    let accent: Color
    let contentProvider: (Int, StepVisualState) -> StepCellContent
    let onValueDrag: ((Int, Double) -> Void)?
    let onSelectStep: ((Int) -> Void)?
    let onBackgroundTap: (() -> Void)?
    let onOctaveTap: ((Int) -> Void)?
    let advanceStep: (Int) -> Void

    init(
        stepStates: [StepVisualState],
        indexOffset: Int = 0,
        playingStepIndex: Int? = nil,
        selectedStepIndexes: Set<Int> = [],
        accent: Color = StudioTheme.transportAccent,
        contentProvider: @escaping (Int, StepVisualState) -> StepCellContent = { _, _ in .toggle },
        onValueDrag: ((Int, Double) -> Void)? = nil,
        onSelectStep: ((Int) -> Void)? = nil,
        onBackgroundTap: (() -> Void)? = nil,
        onOctaveTap: ((Int) -> Void)? = nil,
        advanceStep: @escaping (Int) -> Void
    ) {
        self.stepStates = stepStates
        self.indexOffset = indexOffset
        self.playingStepIndex = playingStepIndex
        self.selectedStepIndexes = selectedStepIndexes
        self.accent = accent
        self.contentProvider = contentProvider
        self.onValueDrag = onValueDrag
        self.onSelectStep = onSelectStep
        self.onBackgroundTap = onBackgroundTap
        self.onOctaveTap = onOctaveTap
        self.advanceStep = advanceStep
    }

    // 16 columns so a 16-step page is one bar-aligned row of compact cells —
    // the same grid grammar as the slicer step strip.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 16)

    var body: some View {
        ZStack {
            if let onBackgroundTap {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onBackgroundTap)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(stepStates.enumerated()), id: \.offset) { index, state in
                    let absoluteIndex = index + indexOffset
                    StepGridCell(
                        index: absoluteIndex,
                        state: state,
                        isPlaying: playingStepIndex == absoluteIndex,
                        isSelected: isStepSelected(absoluteIndex),
                        accent: accent,
                        content: contentProvider(absoluteIndex, state),
                        valueDragAction: onValueDrag.map { drag in
                            { value in drag(absoluteIndex, value) }
                        },
                        action: { advanceStep(absoluteIndex) },
                        selectAction: onSelectStep.map { select in
                            { select(absoluteIndex) }
                        },
                        octaveTapAction: onOctaveTap.map { octave in
                            { octave(absoluteIndex) }
                        }
                    )
                }
            }
        }
    }

    /// Selection indexes are absolute clip-step indexes, matching
    /// `StepSelectionModel`, so paged grids compose with `indexOffset`.
    func isStepSelected(_ absoluteIndex: Int) -> Bool {
        selectedStepIndexes.contains(absoluteIndex)
    }
}

private struct StepGridCell: View {
    let index: Int
    let state: StepVisualState
    let isPlaying: Bool
    let isSelected: Bool
    let accent: Color
    let content: StepCellContent
    let valueDragAction: ((Double) -> Void)?
    let action: () -> Void
    let selectAction: (() -> Void)?
    let octaveTapAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            Text("\(index + 1)")
                .studioText(.eyebrow)
                .foregroundStyle(labelStyle)

            UnifiedStepCell(
                visualState: state,
                isPlaying: isPlaying,
                isSelected: isSelected,
                content: content,
                accent: accent,
                onTap: performAction,
                onDrag: valueDragAction,
                onSelect: { selectAction?() },
                onOctaveTap: octaveTapAction
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 3)
        // Bold-flat pass: no per-step container plate — the step cell's own
        // outline/fill is the control (one less nesting level). Selection
        // alone draws the outer accent line.
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
        )
        .background {
            #if DEBUG
            StepGridMouseDownProbe(stepIndex: index)
            #else
            EmptyView()
            #endif
        }
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        .studioSelectOnRightClick {
            selectAction?()
        }
        .onChange(of: state) { oldValue, newValue in
            #if DEBUG
            StepGridTapDiagnostics.log(
                "cellStateChanged",
                stepIndex: index,
                details: "\(oldValue.diagnosticName)->\(newValue.diagnosticName)"
            )
            #endif
        }
        .accessibilityLabel("Step \(index + 1)")
        .accessibilityValue(accessibilityText)
        .accessibilityAction(named: "Select Step") {
            selectAction?()
        }
    }

    private func performAction() {
        #if DEBUG
        StepGridTapDiagnostics.log(
            "singleTapRecognized",
            stepIndex: index,
            details: "state=\(state.diagnosticName)"
        )
        #endif
        action()
    }

    private var accessibilityText: String {
        switch state {
        case .off:
            return "Off"
        case .on:
            return "On"
        case .accented:
            return "Accented"
        }
    }

    private var labelStyle: AnyShapeStyle {
        state == .off ? AnyShapeStyle(StudioTheme.mutedText) : AnyShapeStyle(StudioTheme.text)
    }

}

struct StepGridBatchActionAvailability: Equatable, Sendable {
    let hasSelection: Bool
    let hasClipboard: Bool

    var canClear: Bool { hasSelection }
    var canCopy: Bool { hasSelection }
    var canPaste: Bool { hasSelection && hasClipboard }
}

struct StepGridBatchActionBar: View {
    let hasSelection: Bool
    let canPaste: Bool
    let onClear: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void

    private var availability: StepGridBatchActionAvailability {
        StepGridBatchActionAvailability(hasSelection: hasSelection, hasClipboard: canPaste)
    }

    var body: some View {
        HStack(spacing: StudioMetrics.Spacing.tight) {
            actionButton("Clear", systemImage: "xmark", isEnabled: availability.canClear, action: onClear)
            actionButton("Copy", systemImage: "doc.on.doc", isEnabled: availability.canCopy, action: onCopy)
            actionButton("Paste", systemImage: "doc.on.clipboard", isEnabled: availability.canPaste, action: onPaste)
        }
        .fixedSize()
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step actions")
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .studioText(.labelBold)
                .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText)
                .padding(.horizontal, StudioMetrics.Spacing.compact)
                .frame(height: 30)
                .background(
                    StudioTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(title)
    }
}

struct StepPitchKeyboardModel: Equatable, Sendable {
    static let minimumOctave = -1
    static let maximumOctave = 9

    var octave: Int

    init(octave: Int) {
        self.octave = min(max(octave, Self.minimumOctave), Self.maximumOctave)
    }

    var canSelectLowerOctave: Bool { octave > Self.minimumOctave }
    var canSelectHigherOctave: Bool { octave < Self.maximumOctave }

    func midiNote(forPitchClass pitchClass: Int) -> Int? {
        guard (0..<12).contains(pitchClass) else { return nil }
        let note = (octave + 1) * 12 + pitchClass
        return (0...127).contains(note) ? note : nil
    }
}

struct StepPitchKeyboard: View {
    @Binding var octave: Int
    let accent: Color
    let isEnabled: Bool
    let onSelectNote: (Int) -> Void

    private let whiteKeyClasses = [0, 2, 4, 5, 7, 9, 11]
    private let blackKeySpecs: [(pitchClass: Int, boundary: CGFloat)] = [
        (1, 1), (3, 2), (6, 4), (8, 5), (10, 6)
    ]

    var body: some View {
        HStack(alignment: .top, spacing: StudioMetrics.Spacing.standard) {
            keyboard
            octaveSelector
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step pitch keyboard")
        .accessibilityValue(isEnabled ? "Octave \(model.octave)" : "Select a triggered step")
    }

    private var model: StepPitchKeyboardModel {
        StepPitchKeyboardModel(octave: octave)
    }

    private var keyboard: some View {
        GeometryReader { geometry in
            let whiteWidth = geometry.size.width / CGFloat(whiteKeyClasses.count)
            let blackWidth = min(44, max(24, whiteWidth * 0.64))

            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(whiteKeyClasses, id: \.self) { pitchClass in
                        keyButton(pitchClass: pitchClass, isBlack: false)
                            .frame(width: max(1, whiteWidth - 2), height: 72)
                    }
                }

                ForEach(blackKeySpecs, id: \.pitchClass) { spec in
                    keyButton(pitchClass: spec.pitchClass, isBlack: true)
                        .frame(width: blackWidth, height: 45)
                        .offset(x: whiteWidth * spec.boundary - blackWidth / 2 - 1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
    }

    private func keyButton(pitchClass: Int, isBlack: Bool) -> some View {
        let midiNote = model.midiNote(forPitchClass: pitchClass)
        let enabled = isEnabled && midiNote != nil
        let label = midiNote.flatMap(DAWNoteName.string(forMIDINote:)) ?? ""

        return Button {
            guard let midiNote else { return }
            onSelectNote(midiNote)
        } label: {
            Text(label)
                .font(.system(size: isBlack ? 9 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(isBlack ? StudioTheme.text : StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, isBlack ? 5 : 7)
                .background(isBlack ? StudioTheme.background : StudioTheme.inset)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 3,
                        bottomLeadingRadius: 6,
                        bottomTrailingRadius: 6,
                        topTrailingRadius: 3,
                        style: .continuous
                    )
                    .stroke(enabled ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label.isEmpty ? "Unavailable pitch" : label)
    }

    private var octaveSelector: some View {
        VStack(spacing: StudioMetrics.Spacing.hairline) {
            octaveButton(systemImage: "chevron.up", isEnabled: model.canSelectHigherOctave) {
                octave = min(model.octave + 1, StepPitchKeyboardModel.maximumOctave)
            }

            Text("OCT \(model.octave)")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.text)
                .frame(width: 54, height: 24)

            octaveButton(systemImage: "chevron.down", isEnabled: model.canSelectLowerOctave) {
                octave = max(model.octave - 1, StepPitchKeyboardModel.minimumOctave)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Octave")
    }

    private func octaveButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText)
                .frame(width: 54, height: 22)
                .background(
                    StudioTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

#if DEBUG
enum StepGridTapDiagnostics {
    static func log(_ event: String, stepIndex: Int? = nil, details: String = "") {
        let stepText = stepIndex.map { " step=\($0 + 1)" } ?? ""
        let detailText = details.isEmpty ? "" : " \(details)"
        NSLog(
            "[StepGridTap] t=%.6f%@ %@%@",
            ProcessInfo.processInfo.systemUptime,
            stepText,
            event,
            detailText
        )
    }

    static func elapsedMilliseconds(since start: TimeInterval) -> String {
        String(format: "%.3fms", (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }

    static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

extension StepVisualState {
    var diagnosticName: String {
        switch self {
        case .off:
            return "off"
        case .on:
            return "on"
        case .accented:
            return "accented"
        }
    }
}

private struct StepGridMouseDownProbe: NSViewRepresentable {
    let stepIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(stepIndex: stepIndex)
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        context.coordinator.stepIndex = stepIndex
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.stepIndex = stepIndex
        context.coordinator.view = nsView
        context.coordinator.installMonitor()
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: Coordinator) {
        _ = nsView
        coordinator.removeMonitor()
    }

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            _ = point
            return nil
        }
    }

    final class Coordinator {
        var stepIndex: Int
        weak var view: ProbeView?
        private var monitor: Any?

        init(stepIndex: Int) {
            self.stepIndex = stepIndex
        }

        deinit {
            removeMonitor()
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self,
                      let view,
                      event.window === view.window
                else {
                    return event
                }

                let point = view.convert(event.locationInWindow, from: nil)
                if view.bounds.contains(point) {
                    StepGridTapDiagnostics.log("mouseDown", stepIndex: stepIndex)
                }

                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
#endif

#Preview {
    StepGridView(
        stepStates: [.on, .off, .accented, .off, .on, .off, .accented, .off, .on, .accented, .off, .off, .on, .on, .accented, .off],
        playingStepIndex: 4,
        selectedStepIndexes: [2, 9],
        accent: StudioTheme.transportAccent,
        onSelectStep: { _ in },
        advanceStep: { _ in }
    )
    .padding()
}
