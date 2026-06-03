import Observation
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
    @State private var model = AudioPreferencesModel()

    var body: some View {
        Form {
            if let missingDeviceMessage = model.missingDeviceMessage {
                Text(missingDeviceMessage)
                    .foregroundStyle(.orange)
            }

            Section("Input Device") {
                Picker("Input", selection: $model.selectedInputDeviceUID) {
                    ForEach(model.inputDevices) { device in
                        Text(model.label(for: device)).tag(Optional(device.uid))
                    }
                }
                .disabled(model.isApplying || model.inputDevices.isEmpty)
            }

            Section("Output Device") {
                Picker("Output", selection: $model.selectedOutputDeviceUID) {
                    ForEach(model.outputDevices) { device in
                        Text(model.label(for: device)).tag(Optional(device.uid))
                    }
                }
                .disabled(model.isApplying || model.outputDevices.isEmpty)
            }

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .foregroundStyle(model.statusColor)
            }

            HStack {
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isApplying)

                Button {
                    model.applySelection()
                } label: {
                    if model.isApplying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Apply", systemImage: "checkmark.circle")
                    }
                }
                .disabled(model.isApplying || !model.canApply)
            }
        }
        .padding()
        .onAppear {
            model.refresh()
        }
    }
}

@MainActor
@Observable
private final class AudioPreferencesModel {
    private enum ApplyState: Equatable {
        case idle
        case applying
        case success
        case failure(String)
    }

    private let coordinator: AudioDeviceSwitchCoordinator
    var inputDevices: [AudioDeviceDescriptor] = []
    var outputDevices: [AudioDeviceDescriptor] = []
    var selectedInputDeviceUID: String?
    var selectedOutputDeviceUID: String?
    var missingInputDeviceUID: String?
    var missingOutputDeviceUID: String?
    private var applyState: ApplyState = .idle

    init(coordinator: AudioDeviceSwitchCoordinator = AudioDeviceSwitchCoordinator { inputUID, outputUID in
        try SequencerDocumentSessionRegistry.applyAudioDeviceUIDsToActiveSessions(
            inputUID: inputUID,
            outputUID: outputUID
        )
    }) {
        self.coordinator = coordinator
    }

    var isApplying: Bool {
        applyState == .applying
    }

    var canApply: Bool {
        selectedInputDeviceUID != nil || selectedOutputDeviceUID != nil
    }

    var missingDeviceMessage: String? {
        let missing = [missingInputDeviceUID, missingOutputDeviceUID].compactMap(\.self)
        guard !missing.isEmpty else { return nil }
        return "Previously selected device missing; using system default."
    }

    var statusMessage: String? {
        switch applyState {
        case .idle:
            nil
        case .applying:
            "Applying audio device selection..."
        case .success:
            "Audio devices applied."
        case let .failure(message):
            message
        }
    }

    var statusColor: Color {
        switch applyState {
        case .failure:
            .red
        case .success:
            .green
        default:
            .secondary
        }
    }

    func refresh() {
        inputDevices = coordinator.devices(direction: .input)
        outputDevices = coordinator.devices(direction: .output)
        let startup = coordinator.loadStartupPreference()
        selectedInputDeviceUID = startup.resolvedInputDeviceUID ?? inputDevices.first?.uid
        selectedOutputDeviceUID = startup.resolvedOutputDeviceUID ?? outputDevices.first?.uid
        missingInputDeviceUID = startup.missingInputDeviceUID
        missingOutputDeviceUID = startup.missingOutputDeviceUID
    }

    func applySelection() {
        applyState = .applying
        do {
            let result = try coordinator.apply(
                inputUID: selectedInputDeviceUID,
                outputUID: selectedOutputDeviceUID
            )
            selectedInputDeviceUID = result.appliedInputDeviceUID
            selectedOutputDeviceUID = result.appliedOutputDeviceUID
            missingInputDeviceUID = nil
            missingOutputDeviceUID = nil
            applyState = .success
        } catch {
            applyState = .failure(error.localizedDescription)
            refresh()
        }
    }

    func label(for device: AudioDeviceDescriptor) -> String {
        "\(device.displayName) (\(device.channelCount) ch)"
    }
}

#Preview {
    PreferencesView()
}
