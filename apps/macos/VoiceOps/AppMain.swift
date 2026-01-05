import AppKit
import Carbon
import Combine
import SwiftUI

@main
struct VoiceOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusIdleTitle = "konh"
    private var statusItem: NSStatusItem?
    private var panel: OverlayPanel?
    private var previewPanel: PreviewPanel?
    private let previewModel = PreviewModel()
    private var clipboardHotKeyPreference = HotKeyPreference.defaultValue
    private var activationPreference = ActivationKeyPreference.defaultValue
    private var hotKeyDefaultsObserver: Any?
    private var settingsWindowController: NSWindowController?
    private let fnMonitor = FnKeyMonitor()
    private let fnSession = FnSessionController()
    private let clipboardObserver = ClipboardObserver.shared
    private let clipboardPanel = ClipboardHistoryPanelController.shared
    private let sidecarLauncher = SidecarLauncher.shared
    private var fnHoldActive = false
    private var cancellables = Set<AnyCancellable>()

    private let pipeline = PipelineController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupOverlay()
        setupPreviewPanel()
        setupShortcuts()
        setupFnMonitor()
        bindPipeline()
        Permissions.requestInputMonitoringIfNeeded()
        clipboardObserver.start()
        sidecarLauncher.startAll()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshPermissionState()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = statusIdleTitle

        let menu = NSMenu()
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        let revealItem = NSMenuItem(title: "Reveal App in Finder", action: #selector(revealApp), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")

        preferencesItem.target = self
        revealItem.target = self
        quitItem.target = self

        menu.addItem(preferencesItem)
        menu.addItem(revealItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func setupOverlay() {
        let view = OverlayView().environmentObject(pipeline)
        panel = OverlayPanel(rootView: view)
        panel?.onSubmit = { [weak self] in
            self?.pipeline.insertToFocusedApp()
        }
        panel?.onCancel = { [weak self] in
            self?.pipeline.cancel()
        }
    }

    private func setupPreviewPanel() {
        let view = PreviewView(model: previewModel)
        previewPanel = PreviewPanel(rootView: view)
    }

    private func setupShortcuts() {
        activationPreference = ActivationKeyPreference.load()
        fnMonitor.updateActivationKey(keyCode: activationPreference.keyCode, modifiers: activationPreference.modifiers)
        clipboardHotKeyPreference = HotKeyPreference.load()
        fnMonitor.updateClipboardShortcut(keyCode: clipboardHotKeyPreference.keyCode, modifiers: clipboardHotKeyPreference.modifiers)
        hotKeyDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadActivationKeyIfNeeded()
                self?.reloadClipboardHotKeyIfNeeded()
            }
        }
    }

    private func reloadClipboardHotKeyIfNeeded() {
        let latest = HotKeyPreference.load()
        guard latest != clipboardHotKeyPreference else { return }
        clipboardHotKeyPreference = latest
        fnMonitor.updateClipboardShortcut(keyCode: latest.keyCode, modifiers: latest.modifiers)
    }

    private func reloadActivationKeyIfNeeded() {
        let latest = ActivationKeyPreference.load()
        guard latest != activationPreference else { return }
        activationPreference = latest
        fnMonitor.updateActivationKey(keyCode: latest.keyCode, modifiers: latest.modifiers)
    }

    private func setupFnMonitor() {
        fnMonitor.onFnDown = { [weak self] in
            self?.handleFnDown()
        }
        fnMonitor.onFnUp = { [weak self] in
            self?.handleFnUp()
        }
        fnMonitor.onClipboardToggle = { [weak self] in
            self?.clipboardPanel.toggle()
        }
        fnSession.onIndicatorChange = { [weak self] state in
            self?.updateStatusIndicator(state)
        }
        fnSession.onPreviewText = { [weak self] text in
            self?.previewModel.text = text
        }
        fnMonitor.start()
    }

    private func handleFnDown() {
        guard !fnHoldActive else { return }
        fnHoldActive = true
        clipboardPanel.hide()
        panel?.hide()
        previewModel.text = ""
        previewModel.state = .recording
        previewPanel?.show()
        Permissions.requestAccessibilityIfNeeded()
        Task { await fnSession.startSession() }
    }

    private func handleFnUp() {
        guard fnHoldActive else { return }
        fnHoldActive = false
        fnSession.endSession()
    }

    private func updateStatusIndicator(_ state: FnSessionController.IndicatorState) {
        switch state {
        case .idle:
            previewModel.state = .idle
            if !fnHoldActive {
                previewPanel?.hide()
            }
        case .recording:
            previewModel.state = .recording
        case .processing:
            previewModel.state = .processing
        }
    }

    private func bindPipeline() {
        pipeline.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if self?.fnHoldActive == true {
                    self?.panel?.hide()
                    return
                }
                switch state {
                case .idle:
                    self?.panel?.hide()
                default:
                    self?.panel?.show()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        sidecarLauncher.stopAll()
        if let observer = hotKeyDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
            hotKeyDefaultsObserver = nil
        }
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindowController == nil {
            settingsWindowController = makeSettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindowController() -> NSWindowController {
        let hostingController = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.setContentSize(NSSize(width: 560, height: 420))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return NSWindowController(window: window)
    }

    @objc private func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func refreshPermissionState() {
        if Permissions.hasInputMonitoring() {
            fnMonitor.ensureEventTap()
        }
    }
}

struct HotKeySettingsView: View {
    @State private var activationKeyCode: UInt32
    @State private var activationModifiers: UInt32
    @State private var clipboardKeyCode: UInt32
    @State private var clipboardModifiers: UInt32

    init() {
        let activation = ActivationKeyPreference.load()
        _activationKeyCode = State(initialValue: activation.keyCode)
        _activationModifiers = State(initialValue: activation.modifiers)
        let clipboard = HotKeyPreference.load()
        _clipboardKeyCode = State(initialValue: clipboard.keyCode)
        _clipboardModifiers = State(initialValue: clipboard.modifiers)
    }

    var body: some View {
        Form {
            Section("Activation") {
                ShortcutRecorderRow(
                    title: "Hold to record",
                    subtitle: "Press and hold to start recording. Release to finish.",
                    requiresModifier: false,
                    defaultKeyCode: ActivationKeyPreference.defaultValue.keyCode,
                    defaultModifiers: ActivationKeyPreference.defaultValue.modifiers,
                    keyCode: $activationKeyCode,
                    modifiers: $activationModifiers
                ) { keyCode, modifiers in
                    ActivationKeyPreference(keyCode: keyCode, modifiers: modifiers).save()
                }
            }
            Section("Clipboard History") {
                ShortcutRecorderRow(
                    title: "Open clipboard history",
                    subtitle: "Toggles the clipboard history panel.",
                    requiresModifier: true,
                    defaultKeyCode: HotKeyPreference.defaultValue.keyCode,
                    defaultModifiers: HotKeyPreference.defaultValue.modifiers,
                    keyCode: $clipboardKeyCode,
                    modifiers: $clipboardModifiers
                ) { keyCode, modifiers in
                    HotKeyPreference(keyCode: keyCode, modifiers: modifiers).save()
                }
            }
        }
        .frame(minWidth: 420)
    }
}

struct PreferencesView: View {
    var body: some View {
        TabView {
            HotKeySettingsView()
                .tabItem {
                    Text("Shortcuts")
                }
            PermissionsPanelView()
                .tabItem {
                    Text("Permissions")
                }
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 360)
    }
}

struct PermissionsPanelView: View {
    @State private var accessibilityAllowed = Permissions.hasAccessibility()
    @State private var inputMonitoringAllowed = Permissions.hasInputMonitoring()
    @State private var microphoneAllowed = Permissions.hasMicrophoneAccess()
    @State private var microphoneStatus = Permissions.microphoneStatusLabel()
    @State private var isRequestingMicrophone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions")
                    .font(.headline)
                Text("Grant the permissions below to keep shortcuts and recording working across apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            PermissionRow(
                title: "Input Monitoring",
                detail: "Required for global shortcuts across all apps.",
                statusText: inputMonitoringAllowed ? "Allowed" : "Denied",
                statusColor: inputMonitoringAllowed ? .green : .red,
                actionTitle: "Open Settings",
                actionEnabled: true,
                action: openInputMonitoringSettings
            )

            PermissionRow(
                title: "Accessibility",
                detail: "Required to inject text and control focus.",
                statusText: accessibilityAllowed ? "Allowed" : "Denied",
                statusColor: accessibilityAllowed ? .green : .red,
                actionTitle: "Open Settings",
                actionEnabled: true,
                action: openAccessibilitySettings
            )

            PermissionRow(
                title: "Microphone",
                detail: "Required to capture audio for transcription.",
                statusText: microphoneStatus,
                statusColor: microphoneStatusColor,
                actionTitle: microphoneActionTitle,
                actionEnabled: !isRequestingMicrophone,
                action: handleMicrophoneAction
            )

            InfoRow(
                title: "App Path",
                value: Bundle.main.bundlePath
            )

            HStack {
                Button("Refresh Status") {
                    refreshStatuses()
                }
                Spacer()
                if allPermissionsGranted {
                    Text("All set")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Note: macOS blocks global shortcuts while Secure Input is active (for example in password fields).")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onAppear {
            refreshStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatuses()
        }
    }

    private var allPermissionsGranted: Bool {
        accessibilityAllowed && inputMonitoringAllowed && microphoneAllowed
    }

    private var microphoneActionTitle: String {
        if isRequestingMicrophone {
            return "Requesting..."
        }
        if Permissions.microphoneNeedsRequest() {
            return "Request Access"
        }
        return "Open Settings"
    }

    private var microphoneStatusColor: Color {
        if microphoneAllowed {
            return .green
        }
        if Permissions.microphoneNeedsRequest() {
            return .orange
        }
        return .red
    }

    private func refreshStatuses() {
        accessibilityAllowed = Permissions.hasAccessibility()
        inputMonitoringAllowed = Permissions.hasInputMonitoring()
        microphoneAllowed = Permissions.hasMicrophoneAccess()
        microphoneStatus = Permissions.microphoneStatusLabel()
    }

    private func openAccessibilitySettings() {
        Permissions.requestAccessibilityIfNeeded()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openInputMonitoringSettings() {
        Permissions.requestInputMonitoringIfNeeded()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleMicrophoneAction() {
        if Permissions.microphoneNeedsRequest() {
            isRequestingMicrophone = true
            Task {
                _ = await Permissions.requestMicrophoneIfNeeded()
                await MainActor.run {
                    isRequestingMicrophone = false
                    refreshStatuses()
                }
            }
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let statusText: String
    let statusColor: Color
    let actionTitle: String
    let actionEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
            Button(actionTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(!actionEnabled)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }
}

struct ShortcutRecorderRow: View {
    let title: String
    let subtitle: String?
    let requiresModifier: Bool
    let defaultKeyCode: UInt32
    let defaultModifiers: UInt32
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    let onSave: (UInt32, UInt32) -> Void

    @State private var isRecording = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var localMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: toggleRecording) {
                    Text(buttonTitle)
                        .font(.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : .primary)
            }
            HStack {
                Button("Reset to Default") {
                    resetToDefault()
                }
                .buttonStyle(.link)
                Spacer()
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(statusIsError ? .red : .secondary)
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var buttonTitle: String {
        isRecording ? "Press shortcut..." : shortcutDisplay
    }

    private var shortcutDisplay: String {
        HotKeyPreference.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        statusMessage = "Recording..."
        statusIsError = false
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard isRecording else { return event }
            if handleRecordingEvent(event) {
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isRecording = false
        if statusMessage == "Recording..." {
            statusMessage = nil
        }
    }

    private func handleRecordingEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            if event.keyCode == UInt16(kVK_Function) {
                let capturedModifiers = normalizedModifiers(event.modifierFlags)
                if requiresModifier && capturedModifiers == 0 {
                    statusMessage = "Add at least one modifier."
                    statusIsError = true
                    return true
                }
                let modifiers = requiresModifier ? capturedModifiers : 0
                return acceptShortcut(keyCode: UInt32(kVK_Function), modifiers: modifiers)
            }
            return true
        case .keyDown:
            if event.keyCode == UInt16(kVK_Escape) {
                statusMessage = "Canceled"
                statusIsError = false
                stopRecording()
                return true
            }
            let capturedModifiers = normalizedModifiers(event.modifierFlags)
            if requiresModifier && capturedModifiers == 0 {
                statusMessage = "Add at least one modifier."
                statusIsError = true
                return true
            }
            return acceptShortcut(keyCode: UInt32(event.keyCode), modifiers: capturedModifiers)
        default:
            return false
        }
    }

    private func acceptShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        self.keyCode = keyCode
        self.modifiers = modifiers
        onSave(keyCode, modifiers)
        statusMessage = "Saved"
        statusIsError = false
        stopRecording()
        return true
    }

    private func resetToDefault() {
        keyCode = defaultKeyCode
        modifiers = defaultModifiers
        onSave(defaultKeyCode, defaultModifiers)
        statusMessage = "Reset to default"
        statusIsError = false
    }

    private func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }
}
