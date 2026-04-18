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

private struct MIDIPreferences: View {
    var body: some View {
        Form {
            Text("MIDI devices will be listed here after Task 9.")
        }.padding()
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
