import AppKit
import Carbon
import Combine
import SwiftUI

@main
struct VoiceOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum FnSession {
        case none
        case pending
        case streaming
        case polish
    }

    private var statusItem: NSStatusItem?
    private var panel: OverlayPanel?
    private var hotKey: HotKeyService?
    private let fnMonitor = FnKeyMonitor()
    private var fnSession: FnSession = .none
    private var fnWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private let pipeline = PipelineController()
    private var toggleItem = NSMenuItem()
    private var insertItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupOverlay()
        setupHotKey()
        setupFnMonitor()
        bindPipeline()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "VO"

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecord), keyEquivalent: "")
        insertItem = NSMenuItem(title: "Insert", action: #selector(insertText), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")

        toggleItem.target = self
        insertItem.target = self
        quitItem.target = self

        insertItem.isEnabled = false

        menu.addItem(toggleItem)
        menu.addItem(insertItem)
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

    private func setupHotKey() {
        do {
            hotKey = try HotKeyService(keyCode: 49, modifiers: UInt32(optionKey)) { [weak self] in
                self?.pipeline.toggleRecord()
            }
        } catch {
            print("HotKey registration failed: \(error)")
        }
    }

    private func setupFnMonitor() {
        Permissions.requestAccessibilityIfNeeded()
        fnMonitor.onFnDown = { [weak self] in
            self?.handleFnDown()
        }
        fnMonitor.onFnUp = { [weak self] in
            self?.handleFnUp()
        }
        fnMonitor.onFnSpace = { [weak self] in
            self?.handleFnSpace()
        }
        fnMonitor.start()
    }

    private func handleFnDown() {
        guard fnSession == .none else { return }
        fnSession = .pending
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.fnSession == .pending else { return }
            self.fnSession = .streaming
            self.pipeline.startStreaming()
        }
        fnWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func handleFnSpace() {
        if fnSession == .pending {
            fnWorkItem?.cancel()
        }
        guard fnSession != .polish else { return }
        fnSession = .polish
        pipeline.startPolishRecording()
    }

    private func handleFnUp() {
        fnWorkItem?.cancel()
        switch fnSession {
        case .streaming:
            pipeline.stopStreaming()
        case .polish:
            pipeline.stopPolishRecording()
        case .pending, .none:
            break
        }
        fnSession = .none
    }

    private func bindPipeline() {
        pipeline.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateMenu(for: state)
                switch state {
                case .idle:
                    self?.panel?.hide()
                default:
                    self?.panel?.show()
                }
            }
            .store(in: &cancellables)
    }

    private func updateMenu(for state: PipelineController.State) {
        switch state {
        case .recording:
            toggleItem.title = "Stop Recording"
        default:
            toggleItem.title = "Start Recording"
        }

        if case .ready = state {
            insertItem.isEnabled = true
        } else {
            insertItem.isEnabled = false
        }
    }

    @objc private func toggleRecord() {
        pipeline.toggleRecord()
    }

    @objc private func insertText() {
        pipeline.insertToFocusedApp()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
