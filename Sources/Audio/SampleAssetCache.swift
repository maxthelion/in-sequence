import AVFoundation
import Foundation

final class PreparedSampleAsset: @unchecked Sendable {
    let sampleID: UUID
    let name: String
    let url: URL
    let fileIdentity: SampleAssetFileIdentity
    let file: AVAudioFile
    let lengthFrames: AVAudioFramePosition
    let sampleRate: Double
    let pcmBuffer: AVAudioPCMBuffer?
    let estimatedByteSize: Int

    init(
        sampleID: UUID,
        name: String,
        url: URL,
        fileIdentity: SampleAssetFileIdentity,
        file: AVAudioFile,
        pcmBuffer: AVAudioPCMBuffer?
    ) {
        self.sampleID = sampleID
        self.name = name
        self.url = url
        self.fileIdentity = fileIdentity
        self.file = file
        self.lengthFrames = file.length
        self.sampleRate = file.processingFormat.sampleRate
        self.pcmBuffer = pcmBuffer
        self.estimatedByteSize = Self.estimatedByteSize(file: file, pcmBuffer: pcmBuffer)
    }

    private static func estimatedByteSize(file: AVAudioFile, pcmBuffer: AVAudioPCMBuffer?) -> Int {
        guard let pcmBuffer else {
            return 0
        }
        let bytesPerFrame = Int(file.processingFormat.streamDescription.pointee.mBytesPerFrame)
        return Int(pcmBuffer.frameLength) * max(1, bytesPerFrame)
    }
}

struct SampleAssetFileIdentity: Equatable, Hashable, Sendable {
    let path: String
    let modifiedAt: Date?
    let fileSize: Int64?
}

final class SampleAssetCache {
    typealias FileOpener = (URL) throws -> AVAudioFile

    enum Readiness: Equatable, Sendable {
        case missing
        case loading
        case ready
        case failed(String)
        case stale

        var diagnosticName: String {
            switch self {
            case .missing:
                return "missing"
            case .loading:
                return "loading"
            case .ready:
                return "ready"
            case .failed:
                return "failed"
            case .stale:
                return "stale"
            }
        }
    }

    private let lock = NSLock()
    private let fileOpener: FileOpener
    private let warmupQueue = DispatchQueue(label: "ai.sequencer.sample-asset-cache", qos: .userInitiated)
    private let memoryBudgetBytes: Int
    private var entriesBySampleID: [UUID: CacheEntry] = [:]
    private var pinnedSampleIDs: Set<UUID> = []
    private var currentByteSize = 0

    private struct CacheEntry {
        var readiness: Readiness
        var asset: PreparedSampleAsset?
        var lastAccessed: TimeInterval
    }

    init(
        memoryBudgetBytes: Int = 128 * 1_024 * 1_024,
        fileOpener: @escaping FileOpener = { try AVAudioFile(forReading: $0) }
    ) {
        self.memoryBudgetBytes = max(1, memoryBudgetBytes)
        self.fileOpener = fileOpener
    }

    func asset(sampleID: UUID, trackID: UUID? = nil) -> PreparedSampleAsset? {
        let (asset, result) = lock.withLock { () -> (PreparedSampleAsset?, String) in
            guard var entry = entriesBySampleID[sampleID] else {
                return (nil, Readiness.missing.diagnosticName)
            }
            entry.lastAccessed = ProcessInfo.processInfo.systemUptime
            entriesBySampleID[sampleID] = entry
            return (entry.asset, entry.readiness.diagnosticName)
        }
        SequencerTimingProbe.sampleAssetCacheLookup(
            sampleID: sampleID,
            trackID: trackID,
            result: asset == nil ? result : "hit"
        )
        return asset
    }

    func readiness(sampleID: UUID) -> Readiness {
        lock.withLock {
            entriesBySampleID[sampleID]?.readiness ?? .missing
        }
    }

    @discardableResult
    func warm(sample: AudioSample, libraryRoot: URL) -> PreparedSampleAsset? {
        markLoading(sampleID: sample.id)
        return load(sample: sample, libraryRoot: libraryRoot)
    }

    func warmAsync(samples: [AudioSample], libraryRoot: URL, pinnedSampleIDs: Set<UUID>) {
        lock.withLock {
            self.pinnedSampleIDs = pinnedSampleIDs
            for sample in samples {
                entriesBySampleID[sample.id] = CacheEntry(
                    readiness: .loading,
                    asset: entriesBySampleID[sample.id]?.asset,
                    lastAccessed: ProcessInfo.processInfo.systemUptime
                )
            }
        }
        warmupQueue.async { [weak self] in
            guard let self else { return }
            for sample in samples {
                _ = self.load(sample: sample, libraryRoot: libraryRoot)
            }
            self.retain(sampleIDs: pinnedSampleIDs)
        }
    }

    func warm(samples: [AudioSample], libraryRoot: URL) {
        for sample in samples {
            _ = warm(sample: sample, libraryRoot: libraryRoot)
        }
    }

    func retain(sampleIDs: Set<UUID>) {
        lock.withLock {
            pinnedSampleIDs = sampleIDs
            evictUnpinnedOverBudget()
        }
    }

    func removeAll() {
        lock.withLock {
            entriesBySampleID.removeAll(keepingCapacity: true)
            pinnedSampleIDs.removeAll(keepingCapacity: true)
            currentByteSize = 0
        }
    }

    private func markLoading(sampleID: UUID) {
        lock.withLock {
            entriesBySampleID[sampleID] = CacheEntry(
                readiness: .loading,
                asset: entriesBySampleID[sampleID]?.asset,
                lastAccessed: ProcessInfo.processInfo.systemUptime
            )
        }
    }

    @discardableResult
    private func load(sample: AudioSample, libraryRoot: URL) -> PreparedSampleAsset? {
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let url = try sample.fileRef.resolve(libraryRoot: libraryRoot)
            let identity = Self.fileIdentity(for: url)
            if let cached = lock.withLock({ entriesBySampleID[sample.id]?.asset }),
               cached.fileIdentity == identity
            {
                lock.withLock {
                    entriesBySampleID[sample.id] = CacheEntry(
                        readiness: .ready,
                        asset: cached,
                        lastAccessed: ProcessInfo.processInfo.systemUptime
                    )
                }
                return cached
            }
            let file = try fileOpener(url)
            let buffer = Self.loadPCMBuffer(from: file)
            file.framePosition = 0
            let asset = PreparedSampleAsset(
                sampleID: sample.id,
                name: sample.name,
                url: url,
                fileIdentity: identity,
                file: file,
                pcmBuffer: buffer
            )
            lock.withLock {
                if let previous = entriesBySampleID[sample.id]?.asset {
                    currentByteSize -= previous.estimatedByteSize
                }
                entriesBySampleID[sample.id] = CacheEntry(
                    readiness: .ready,
                    asset: asset,
                    lastAccessed: ProcessInfo.processInfo.systemUptime
                )
                currentByteSize += asset.estimatedByteSize
                evictUnpinnedOverBudget()
            }
            SequencerTimingProbe.sampleAssetCacheLoad(
                sampleID: sample.id,
                file: url.lastPathComponent,
                duration: ProcessInfo.processInfo.systemUptime - started,
                frames: Int64(file.length),
                result: buffer == nil ? "file-only" : "memory"
            )
            return asset
        } catch {
            lock.withLock {
                entriesBySampleID[sample.id] = CacheEntry(
                    readiness: .failed(String(describing: error)),
                    asset: nil,
                    lastAccessed: ProcessInfo.processInfo.systemUptime
                )
            }
            SequencerTimingProbe.sampleAssetCacheLoad(
                sampleID: sample.id,
                file: sample.name,
                duration: ProcessInfo.processInfo.systemUptime - started,
                frames: 0,
                result: "failed"
            )
            return nil
        }
    }

    private func evictUnpinnedOverBudget() {
        guard currentByteSize > memoryBudgetBytes else { return }
        let candidates = entriesBySampleID
            .filter { !pinnedSampleIDs.contains($0.key) && $0.value.asset != nil }
            .sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        for candidate in candidates {
            guard currentByteSize > memoryBudgetBytes else { break }
            guard let asset = entriesBySampleID[candidate.key]?.asset else { continue }
            entriesBySampleID[candidate.key] = CacheEntry(
                readiness: .stale,
                asset: nil,
                lastAccessed: ProcessInfo.processInfo.systemUptime
            )
            currentByteSize -= asset.estimatedByteSize
            SequencerTimingProbe.sampleAssetCacheEviction(
                sampleID: candidate.key,
                bytes: asset.estimatedByteSize,
                reason: "memory-budget"
            )
        }
    }

    private static func loadPCMBuffer(from file: AVAudioFile) -> AVAudioPCMBuffer? {
        guard file.length > 0,
              file.length <= AVAudioFramePosition(AVAudioFrameCount.max),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(file.length)
              )
        else {
            return nil
        }
        do {
            file.framePosition = 0
            try file.read(into: buffer, frameCount: AVAudioFrameCount(file.length))
            return buffer
        } catch {
            return nil
        }
    }

    private static func fileIdentity(for url: URL) -> SampleAssetFileIdentity {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return SampleAssetFileIdentity(
            path: url.path,
            modifiedAt: values?.contentModificationDate,
            fileSize: values?.fileSize.map(Int64.init)
        )
    }
}
