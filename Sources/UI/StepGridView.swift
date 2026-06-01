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
    let contentProvider: (Int, StepVisualState) -> StepCellContent
    let onValueDrag: ((Int, Double) -> Void)?
    let onDoubleTap: ((Int) -> Void)?
    let advanceStep: (Int) -> Void

    init(
        stepStates: [StepVisualState],
        indexOffset: Int = 0,
        playingStepIndex: Int? = nil,
        contentProvider: @escaping (Int, StepVisualState) -> StepCellContent = { _, _ in .toggle },
        onValueDrag: ((Int, Double) -> Void)? = nil,
        onDoubleTap: ((Int) -> Void)? = nil,
        advanceStep: @escaping (Int) -> Void
    ) {
        self.stepStates = stepStates
        self.indexOffset = indexOffset
        self.playingStepIndex = playingStepIndex
        self.contentProvider = contentProvider
        self.onValueDrag = onValueDrag
        self.onDoubleTap = onDoubleTap
        self.advanceStep = advanceStep
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(stepStates.enumerated()), id: \.offset) { index, state in
                let absoluteIndex = index + indexOffset
                StepGridCell(
                    index: absoluteIndex,
                    state: state,
                    isPlaying: playingStepIndex == absoluteIndex,
                    content: contentProvider(absoluteIndex, state),
                    valueDragAction: onValueDrag.map { drag in
                        { value in drag(absoluteIndex, value) }
                    },
                    action: { advanceStep(absoluteIndex) },
                    inspectAction: onDoubleTap.map { inspect in
                        { inspect(absoluteIndex) }
                    }
                )
            }
        }
    }
}

private struct StepGridCell: View {
    let index: Int
    let state: StepVisualState
    let isPlaying: Bool
    let content: StepCellContent
    let valueDragAction: ((Double) -> Void)?
    let action: () -> Void
    let inspectAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text("\(index + 1)")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(labelStyle)

            UnifiedStepCell(
                visualState: state,
                isPlaying: isPlaying,
                isSelected: false,
                content: content,
                onTap: action,
                onDrag: valueDragAction,
                onSelect: { inspectAction?() }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .background {
            #if DEBUG
            StepGridMouseDownProbe(stepIndex: index)
            #else
            EmptyView()
            #endif
        }
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture {
            #if DEBUG
            StepGridTapDiagnostics.log(
                "singleTapRecognized",
                stepIndex: index,
                details: "state=\(state.diagnosticName)"
            )
            #endif
            action()
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
        .accessibilityAction(named: "Inspect Step") {
            inspectAction?()
        }
        .contextMenu {
            if let inspectAction {
                Button("Inspect Step", action: inspectAction)
            }
        }
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

    private var outlineColor: Color {
        switch state {
        case .off:
            return Color.white.opacity(StudioOpacity.borderSubtle)
        case .on:
            return StudioTheme.cyan.opacity(0.34)
        case .accented:
            return StudioTheme.amber.opacity(0.34)
        }
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
        advanceStep: { _ in }
    )
    .padding()
}
