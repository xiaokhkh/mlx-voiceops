import AVFoundation

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "voiceops.audio.queue")
    private var outputURL: URL?
    private var outputFile: AVAudioFile?
    private var chunkFile: AVAudioFile?
    private var chunkFrames: AVAudioFramePosition = 0
    private var chunkFrameLimit: AVAudioFramePosition = 0
    private var onChunk: ((URL) -> Void)?
    private var streamingEnabled = false
    private var targetFormat: AVAudioFormat?

    func start(
        streaming: Bool,
        chunkDuration: TimeInterval = 1.5,
        onChunk: ((URL) -> Void)? = nil
    ) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceops_\(UUID().uuidString).wav")
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )

        outputURL = url
        outputFile = file
        streamingEnabled = streaming
        self.onChunk = onChunk
        chunkFrames = 0
        chunkFrameLimit = AVAudioFramePosition(format.sampleRate * chunkDuration)
        targetFormat = format

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() throws -> URL {
        guard let url = outputURL else {
            throw NSError(domain: "AudioCaptureService", code: 1)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        flushChunk()
        outputFile = nil
        outputURL = nil
        return url
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputFile = nil
        outputURL = nil
        chunkFile = nil
        chunkFrames = 0
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let format = targetFormat else { return }

        let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity)!
        copy.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
            memcpy(dst[0], src[0], bytes)
        }

        audioQueue.async { [weak self] in
            guard let self else { return }
            try? self.outputFile?.write(from: copy)

            guard self.streamingEnabled else { return }
            if self.chunkFile == nil {
                self.chunkFile = try? AVAudioFile(
                    forWriting: FileManager.default.temporaryDirectory
                        .appendingPathComponent("voiceops_chunk_\(UUID().uuidString).wav"),
                    settings: format.settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
                self.chunkFrames = 0
            }
            if let chunkFile = self.chunkFile {
                try? chunkFile.write(from: copy)
                self.chunkFrames += AVAudioFramePosition(copy.frameLength)
                if self.chunkFrames >= self.chunkFrameLimit {
                    let url = chunkFile.url
                    self.chunkFile = nil
                    self.chunkFrames = 0
                    self.onChunk?(url)
                }
            }
        }
    }

    private func flushChunk() {
        guard streamingEnabled, let chunkFile = chunkFile else { return }
        let url = chunkFile.url
        self.chunkFile = nil
        self.chunkFrames = 0
        onChunk?(url)
    }
}
