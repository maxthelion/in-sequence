import AVFoundation
import SwiftUI

struct AUEffectEditorPanel: View {
    let title: String
    let subtitle: String
    let accent: Color
    let prepare: () -> Void
    let currentAudioUnit: () -> AVAudioUnit?
    let parameterReadout: () -> [AUParameterDescriptor]?
    let openWindow: (AVAudioUnit) -> Void

    @State private var pollTask: Task<Void, Never>?
    @State private var parameters: [AUParameterDescriptor]?
    @State private var isOpening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button(action: prepareAndOpen) {
                    Label(isOpening ? "Opening" : "Open Plug-In", systemImage: "macwindow")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.background)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isOpening)
                .help("Open AU plug-in editor")

                StudioCircleIconButton(
                    systemName: "arrow.clockwise",
                    size: StudioMetrics.ControlSize.small,
                    help: "Refresh AU parameters",
                    action: refreshParameters
                )
            }

            parameterSummary
        }
        .onAppear { refreshParameters() }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    @ViewBuilder
    private var parameterSummary: some View {
        if let params = parameters {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("MACRO CANDIDATES")
                        .studioText(.eyebrow)
                        .foregroundStyle(StudioTheme.mutedText)
                    Text("\(params.count)")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.text)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(StudioTheme.subtleFill, in: Capsule())
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 74), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                    ForEach(Array(params.prefix(8).enumerated()), id: \.offset) { index, param in
                        macroCandidate(index: index, param: param)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing AU parameters")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
    }

    private func macroCandidate(index: Int, param: AUParameterDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("M\(index + 1)")
                .studioText(.eyebrow)
                .foregroundStyle(StudioTheme.mutedText)
            Text(param.displayName)
                .studioText(.micro)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(StudioTheme.background, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func prepareAndOpen() {
        isOpening = true
        refreshParameters()
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            for _ in 0..<20 {
                if parameters == nil, let readout = parameterReadout() {
                    parameters = readout
                }
                if let audioUnit = currentAudioUnit() {
                    openWindow(audioUnit)
                    isOpening = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            isOpening = false
        }
    }

    private func refreshParameters() {
        prepare()
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            for _ in 0..<20 {
                if let readout = parameterReadout() {
                    parameters = readout
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            parameters = parameterReadout()
        }
    }
}
