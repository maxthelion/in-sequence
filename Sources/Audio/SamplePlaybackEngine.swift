import Foundation
import AVFoundation

struct VoiceHandle: Equatable, Hashable {
    fileprivate let id: UUID
}

protocol SamplePlaybackSink: AnyObject {
    func start() throws
    func stop()
    func play(sampleURL: URL, settings: SamplerSettings, at when: AVAudioTime?) -> VoiceHandle?
    func audition(sampleURL: URL)
    func stopAudition()
}

final class SamplePlaybackEngine: SamplePlaybackSink {
    private static let mainVoiceCount = 16
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var mainVoices: [AVAudioPlayerNode] = []
    private var mainVoiceHandles: [UUID] = []
    private var nextVoiceIndex = 0
    private let previewNode = AVAudioPlayerNode()
    private var fileCache: [URL: AVAudioFile] = [:]
    private var isStarted = false

    init() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        for _ in 0..<Self.mainVoiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mixer, format: nil)
            mainVoices.append(node)
            mainVoiceHandles.append(UUID())
        }
        engine.attach(previewNode)
        engine.connect(previewNode, to: mixer, format: nil)
    }

    func start() throws {
        guard !isStarted else { return }
        try engine.start()
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        for voice in mainVoices { voice.stop() }
        previewNode.stop()
        engine.stop()
        isStarted = false
    }

    @discardableResult
    func play(sampleURL: URL, settings: SamplerSettings, at when: AVAudioTime? = nil) -> VoiceHandle? {
        guard isStarted else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }

        let voice = mainVoices[nextVoiceIndex]
        let handleID = UUID()
        mainVoiceHandles[nextVoiceIndex] = handleID
        nextVoiceIndex = (nextVoiceIndex &+ 1) % mainVoices.count

        voice.stop()
        voice.volume = linearGain(dB: settings.gain)
        voice.scheduleFile(file, at: when, completionHandler: nil)
        voice.play()

        return VoiceHandle(id: handleID)
    }

    func stopVoice(_ handle: VoiceHandle) {
        guard let idx = mainVoiceHandles.firstIndex(of: handle.id) else { return }
        mainVoices[idx].stop()
    }

    func stopAllMainVoices() {
        for voice in mainVoices { voice.stop() }
    }

    func audition(sampleURL: URL) {
        guard isStarted else { return }
        guard let file = cachedFile(url: sampleURL) else { return }
        previewNode.stop()
        previewNode.volume = 1.0
        previewNode.scheduleFile(file, at: nil, completionHandler: nil)
        previewNode.play()
    }

    func stopAudition() {
        previewNode.stop()
    }

    private func cachedFile(url: URL) -> AVAudioFile? {
        if let f = fileCache[url] { return f }
        guard let f = try? AVAudioFile(forReading: url) else { return nil }
        if fileCache.count >= 64 {
            fileCache.removeAll(keepingCapacity: true)
        }
        fileCache[url] = f
        return f
    }

    private func linearGain(dB: Double) -> Float {
        Float(pow(10, dB / 20))
    }
}
