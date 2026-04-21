import SwiftUI

struct GeneratedNotesPreview: View {
    let pipeline: GeneratedSourcePipeline
    let clipChoices: [ClipPoolEntry]

    var body: some View {
        let preview = previewSteps(for: pipeline, clipChoices: clipChoices)
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(preview.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                            VStack(alignment: .leading, spacing: 4) {
                                if preview[index].isEmpty {
                                    Text("—")
                                        .foregroundStyle(StudioTheme.mutedText)
                                } else {
                                    ForEach(preview[index], id: \.self) { label in
                                        Text(label)
                                            .foregroundStyle(StudioTheme.text)
                                    }
                                }
                            }
                            .studioText(.labelBold)
                        }
                        .frame(width: 84, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                    }
                }
            }
            Text("Preview is generated from the current trigger stage and pitch expander.")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }
}
