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
    // TODO: replace these snapshots with observation-driven invalidation once MIDIClient
    // subscribes to kMIDIMsgObjectAdded / kMIDIMsgObjectRemoved notifications and mutates
    // tracked state. Until then, the user hits Refresh to re-read the system endpoint list
    // into these @State snapshots (cheaper than rebuilding the whole view tree via .id()).
    @State private var sources: [MIDIEndpoint] = MIDISession.shared.sources
    @State private var destinations: [MIDIEndpoint] = MIDISession.shared.destinations
    @State private var appInput: MIDIEndpoint? = MIDISession.shared.appInput
    @State private var appOutput: MIDIEndpoint? = MIDISession.shared.appOutput

    var body: some View {
        Form {
            Section("Inputs") {
                if sources.isEmpty {
                    Text("No MIDI input endpoints found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources) { endpoint in
                        Text(endpoint.displayName)
                    }
                }
            }
            Section("Outputs") {
                if destinations.isEmpty {
                    Text("No MIDI output endpoints found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(destinations) { endpoint in
                        Text(endpoint.displayName)
                    }
                }
            }
            Section("Virtual (this app)") {
                if let out = appOutput {
                    LabeledContent("Out", value: out.displayName)
                }
                if let input = appInput {
                    LabeledContent("In", value: input.displayName)
                }
                if appInput == nil && appOutput == nil {
                    Text("Virtual endpoints unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Refresh") { refresh() }
            }
        }
        .padding()
    }

    private func refresh() {
        let session = MIDISession.shared
        sources = session.sources
        destinations = session.destinations
        appInput = session.appInput
        appOutput = session.appOutput
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
