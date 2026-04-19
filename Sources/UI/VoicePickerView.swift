import SwiftUI

struct VoicePickerView: View {
    let title: String
    let choices: [AudioInstrumentChoice]
    let recentVoices: [RecentVoice]
    @Binding var selectedInstrument: AudioInstrumentChoice
    var onRecallRecent: (RecentVoice) -> Void = { _ in }
    var onSaveCurrent: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            if !recentVoices.isEmpty {
                Menu {
                    ForEach(recentVoices) { voice in
                        Button(voice.name) {
                            onRecallRecent(voice)
                        }
                    }
                } label: {
                    Label("Recall Recent Voice", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }

            Picker("Instrument", selection: $selectedInstrument) {
                ForEach(choices, id: \.self) { instrument in
                    Text(instrument.displayName).tag(instrument)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Text(selectedInstrument.displayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.text)

                Spacer()

                Button("Save Voice Snapshot") {
                    onSaveCurrent()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
