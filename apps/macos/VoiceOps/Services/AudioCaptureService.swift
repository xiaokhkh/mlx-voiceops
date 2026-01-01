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
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    func start(
        streaming: Bool,
        chunkDuration: TimeInterval = 1.5,
        onChunk: ((URL) -> Void)? = nil
    ) throws {
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceops_\(UUID().uuidString).wav")
        let file = try AVAudioFile(
            forWriting: url,
            settings: target.settings,
            commonFormat: target.commonFormat,
            interleaved: target.isInterleaved
        )

        outputURL = url
        outputFile = file
        streamingEnabled = streaming
        self.onChunk = onChunk
        chunkFrames = 0
        chunkFrameLimit = AVAudioFramePosition(target.sampleRate * chunkDuration)
        targetFormat = target

        let input = engine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)
        inputFormat = hwFormat
        if hwFormat.sampleRate != target.sampleRate || hwFormat.channelCount != target.channelCount {
            converter = AVAudioConverter(from: hwFormat, to: target)
        } else {
            converter = nil
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
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
        converter = nil
        inputFormat = nil
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
        converter = nil
        inputFormat = nil
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let format = targetFormat else { return }

        let copy: AVAudioPCMBuffer
        if let converter {
            let ratio = format.sampleRate / (inputFormat?.sampleRate ?? format.sampleRate)
            let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outFrames)!
            var error: NSError?
            var consumed = false
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            if status == .haveData {
                copy = outBuffer
            } else {
                return
            }
        } else {
            let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity)!
            outBuffer.frameLength = buffer.frameLength
            if let src = buffer.floatChannelData, let dst = outBuffer.floatChannelData {
                let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
                memcpy(dst[0], src[0], bytes)
            }
            copy = outBuffer
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
