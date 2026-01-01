import AVFoundation

final class AudioCaptureService: NSObject {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceops_\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        recorder.record()

        self.recorder = recorder
        self.outputURL = url
    }

    func stop() throws -> URL {
        guard let recorder = recorder, let url = outputURL else {
            throw NSError(domain: "AudioCaptureService", code: 1)
        }
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        return url
    }

    func cancel() {
        recorder?.stop()
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        outputURL = nil
    }
}
