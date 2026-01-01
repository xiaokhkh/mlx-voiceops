import AppKit
import Foundation

@MainActor
final class PipelineController: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case generating
        case ready
        case error(String)
    }

    private enum ActiveSession {
        case manual
        case streaming
        case polish
    }

    @Published var state: State = .idle
    @Published var mode: Mode = .polish
    @Published var transcript: String = ""
    @Published var output: String = ""

    private let asr = ASRClient()
    private let llm = LLMClient()
    private let injector = InputInjector()
    private let audio = AudioCaptureService()
    private var targetApp: NSRunningApplication?
    private var activeSession: ActiveSession?
    private var chunkQueue: [URL] = []
    private var isProcessingChunk = false
    private var endRequested = false
    private let chunkDuration: TimeInterval = 1.5

    func toggleRecord() {
        switch state {
        case .idle, .ready, .error:
            Task { await startRecording() }
        case .recording:
            Task { await stopAndProcess() }
        default:
            break
        }
    }

    func cancel() {
        if case .recording = state {
            audio.cancel()
        }
        chunkQueue.removeAll()
        isProcessingChunk = false
        endRequested = false
        activeSession = nil
        transcript = ""
        output = ""
        state = .idle
        targetApp = nil
    }

    func insertToFocusedApp() {
        guard case .ready = state else { return }
        let text = output.isEmpty ? transcript : output
        Permissions.requestAccessibilityIfNeeded()

        if let app = targetApp {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let didInject = injector.insertViaTyping(text)
            if !didInject {
                _ = injector.insertViaPaste(text)
            }
            state = .idle
            targetApp = nil
        }
    }

    func startStreaming() {
        Task { await startStreamingSession() }
    }

    func stopStreaming() {
        Task { await stopStreamingSession() }
    }

    func startPolishRecording() {
        Task { await startPolishSession() }
    }

    func stopPolishRecording() {
        Task { await stopPolishSession() }
    }

    private func startRecording() async {
        let granted = await Permissions.requestMicrophoneIfNeeded()
        guard granted else {
            state = .error("Microphone permission denied")
            return
        }

        transcript = ""
        output = ""

        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = app
        } else {
            targetApp = nil
        }

        do {
            try audio.start(streaming: false)
            activeSession = .manual
            state = .recording
        } catch {
            state = .error("Audio start failed: \(error)")
        }
    }

    private func stopAndProcess() async {
        do {
            let wavURL = try audio.stop()
            state = .transcribing
            transcript = try await asr.transcribe(wavURL: wavURL)

            state = .generating
            output = try await llm.generate(mode: mode, text: transcript)

            state = .ready
            activeSession = nil
        } catch {
            state = .error("Pipeline failed: \(error)")
        }
    }

    private func startStreamingSession() async {
        switch state {
        case .idle, .ready, .error:
            break
        default:
            return
        }
        let granted = await Permissions.requestMicrophoneIfNeeded()
        guard granted else {
            state = .error("Microphone permission denied")
            return
        }

        Permissions.requestAccessibilityIfNeeded()
        transcript = ""
        output = ""
        activeSession = .streaming
        endRequested = false
        chunkQueue.removeAll()

        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = app
        } else {
            targetApp = nil
        }

        do {
            try audio.start(streaming: true, chunkDuration: chunkDuration) { [weak self] url in
                Task { @MainActor in
                    self?.enqueueChunk(url)
                }
            }
            state = .recording
        } catch {
            state = .error("Audio start failed: \(error)")
        }
    }

    private func stopStreamingSession() async {
        guard activeSession == .streaming else { return }
        endRequested = true
        do {
            _ = try audio.stop()
        } catch {
            state = .error("Audio stop failed: \(error)")
            finishStreaming()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if self.endRequested && !self.isProcessingChunk && self.chunkQueue.isEmpty {
                self.finishStreaming()
            }
        }
    }

    private func finishStreaming() {
        endRequested = false
        activeSession = nil
        state = .idle
        targetApp = nil
    }

    private func enqueueChunk(_ url: URL) {
        chunkQueue.append(url)
        if !isProcessingChunk {
            Task { await processNextChunk() }
        }
    }

    private func processNextChunk() async {
        guard !chunkQueue.isEmpty else {
            isProcessingChunk = false
            if endRequested {
                finishStreaming()
            }
            return
        }

        isProcessingChunk = true
        let url = chunkQueue.removeFirst()
        do {
            let text = try await asr.transcribe(wavURL: url)
            try? FileManager.default.removeItem(at: url)
            await appendStreamingText(text)
        } catch {
            state = .error("Streaming failed: \(error)")
        }
        await processNextChunk()
    }

    private func appendStreamingText(_ text: String) async {
        guard activeSession == .streaming else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let needsSpace = !transcript.isEmpty &&
            !(transcript.last?.isWhitespace ?? true) &&
            !(trimmed.first?.isWhitespace ?? true)
        let chunk = needsSpace ? " " + trimmed : trimmed
        transcript += chunk

        if let app = targetApp {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        let didInject = injector.insertViaTyping(chunk)
        if !didInject {
            _ = injector.insertViaPaste(chunk)
        }
    }

    private func startPolishSession() async {
        switch state {
        case .idle, .ready, .error:
            break
        default:
            return
        }
        let granted = await Permissions.requestMicrophoneIfNeeded()
        guard granted else {
            state = .error("Microphone permission denied")
            return
        }

        Permissions.requestAccessibilityIfNeeded()
        transcript = ""
        output = ""
        activeSession = .polish

        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = app
        } else {
            targetApp = nil
        }

        do {
            try audio.start(streaming: false)
            state = .recording
        } catch {
            state = .error("Audio start failed: \(error)")
        }
    }

    private func stopPolishSession() async {
        guard activeSession == .polish else { return }
        do {
            let wavURL = try audio.stop()
            state = .transcribing
            transcript = try await asr.transcribe(wavURL: wavURL)

            state = .generating
            output = try await llm.generate(mode: .polish, text: transcript)

            let text = output.isEmpty ? transcript : output
            if let app = targetApp {
                app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
            let didInject = injector.insertViaTyping(text)
            if !didInject {
                _ = injector.insertViaPaste(text)
            }
            state = .idle
            activeSession = nil
        } catch {
            state = .error("Pipeline failed: \(error)")
        }
    }
}
