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
    private var endRequested = false
    private let chunkDuration: TimeInterval = 1.5
    private var manualTask: Task<Void, Never>?
    private var polishTask: Task<Void, Never>?
    private var streamingStartTask: Task<Void, Never>?
    private var streamingStopTask: Task<Void, Never>?
    private var chunkTask: Task<Void, Never>?

    func toggleRecord() {
        switch state {
        case .idle, .ready, .error:
            guard manualTask == nil else { return }
            manualTask = Task { @MainActor [weak self] in
                await self?.startRecording()
                self?.manualTask = nil
            }
        case .recording:
            guard manualTask == nil else { return }
            manualTask = Task { @MainActor [weak self] in
                await self?.stopAndProcess()
                self?.manualTask = nil
            }
        default:
            break
        }
    }

    func cancel() {
        if case .recording = state {
            audio.cancel()
        }
        manualTask?.cancel()
        polishTask?.cancel()
        streamingStartTask?.cancel()
        streamingStopTask?.cancel()
        chunkTask?.cancel()
        manualTask = nil
        polishTask = nil
        streamingStartTask = nil
        streamingStopTask = nil
        chunkTask = nil
        chunkQueue.removeAll()
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
        guard streamingStartTask == nil else { return }
        streamingStartTask = Task { @MainActor [weak self] in
            await self?.startStreamingSession()
            self?.streamingStartTask = nil
        }
    }

    func stopStreaming() {
        guard streamingStopTask == nil else { return }
        streamingStopTask = Task { @MainActor [weak self] in
            await self?.stopStreamingSession()
            self?.streamingStopTask = nil
        }
    }

    func startPolishRecording() {
        guard polishTask == nil else { return }
        polishTask = Task { @MainActor [weak self] in
            await self?.startPolishSession()
            self?.polishTask = nil
        }
    }

    func stopPolishRecording() {
        guard polishTask == nil else { return }
        polishTask = Task { @MainActor [weak self] in
            await self?.stopPolishSession()
            self?.polishTask = nil
        }
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
            if self.endRequested, self.chunkTask == nil, self.chunkQueue.isEmpty {
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
        if chunkTask == nil {
            chunkTask = Task { @MainActor [weak self] in
                await self?.processChunkQueue()
                self?.chunkTask = nil
            }
        }
    }

    private func processChunkQueue() async {
        while !chunkQueue.isEmpty {
            let url = chunkQueue.removeFirst()
            do {
                let text = try await asr.transcribe(wavURL: url)
                try? FileManager.default.removeItem(at: url)
                await appendStreamingText(text)
            } catch {
                state = .error("Streaming failed: \(error)")
                chunkQueue.removeAll()
                endRequested = false
                break
            }
        }
        if endRequested {
            finishStreaming()
        }
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
