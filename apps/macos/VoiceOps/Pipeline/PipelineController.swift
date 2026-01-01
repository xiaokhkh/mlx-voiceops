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

    @Published var state: State = .idle
    @Published var mode: Mode = .polish
    @Published var transcript: String = ""
    @Published var output: String = ""

    private let asr = ASRClient()
    private let llm = LLMClient()
    private let injector = InputInjector()
    private let audio = AudioCaptureService()
    private var targetApp: NSRunningApplication?

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
            let didInject = injector.insertViaPaste(text)
            if !didInject {
                copyToClipboard(text)
            }
            state = .idle
            targetApp = nil
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
            try audio.start()
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
        } catch {
            state = .error("Pipeline failed: \(error)")
        }
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
