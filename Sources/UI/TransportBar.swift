import SwiftUI

struct TransportBar: View {
    @State private var isPlaying: Bool = false
    @State private var bpm: Double = 120
    @State private var swing: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            Button { isPlaying.toggle() } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .frame(width: 16, height: 16)
            }
            Button {} label: {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 16, height: 16)
            }

            Divider().frame(height: 20)

            Text("BPM").foregroundStyle(.secondary).font(.caption)
            Text(String(format: "%.1f", bpm)).monospacedDigit()

            Divider().frame(height: 20)

            Text("1:1:1").monospacedDigit().foregroundStyle(.secondary)

            Spacer()
        }
    }
}

#Preview {
    TransportBar().padding()
}
