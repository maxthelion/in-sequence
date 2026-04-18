import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferences()
                .tabItem { Label("General", systemImage: "gearshape") }
            MIDIPreferences()
                .tabItem { Label("MIDI", systemImage: "pianokeys") }
            AudioPreferences()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralPreferences: View {
    var body: some View {
        Form {
            Text("General preferences placeholder")
        }.padding()
    }
}

/// The MIDI preferences tab uses user-friendly "Inputs" / "Outputs" labels,
/// which map onto CoreMIDI sources / destinations respectively:
///   - "Inputs"  = MIDI coming *into* this app = `MIDISession.sources`
///   - "Outputs" = MIDI going *out* from this app = `MIDISession.destinations`
private struct MIDIPreferences: View {
    @State private var refreshTick: Int = 0

    var body: some View {
        let session = MIDISession.shared

        Form {
            Section("Inputs") {
                if session.sources.isEmpty {
                    Text("No MIDI input endpoints found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.sources) { endpoint in
                        Text(endpoint.displayName)
                    }
                }
            }
            Section("Outputs") {
                if session.destinations.isEmpty {
                    Text("No MIDI output endpoints found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.destinations) { endpoint in
                        Text(endpoint.displayName)
                    }
                }
            }
            Section("Virtual (this app)") {
                if let out = session.appOutput {
                    LabeledContent("Out", value: out.displayName)
                }
                if let input = session.appInput {
                    LabeledContent("In", value: input.displayName)
                }
                if session.appInput == nil && session.appOutput == nil {
                    Text("Virtual endpoints unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Refresh") { refreshTick += 1 }
            }
        }
        .padding()
        .id(refreshTick)
    }
}

private struct AudioPreferences: View {
    var body: some View {
        Form {
            Text("Audio device selection placeholder")
        }.padding()
    }
}

#Preview {
    PreferencesView()
}
