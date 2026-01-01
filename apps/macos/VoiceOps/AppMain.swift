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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusIdleTitle = "konh"
    private var statusItem: NSStatusItem?
    private var panel: OverlayPanel?
    private var previewPanel: PreviewPanel?
    private let previewModel = PreviewModel()
    private var hotKey: HotKeyService?
    private let fnMonitor = FnKeyMonitor()
    private let fnSession = FnSessionController()
    private var fnHoldActive = false
    private var cancellables = Set<AnyCancellable>()

    private let pipeline = PipelineController()
    private var accessItem = NSMenuItem()
    private var revealItem = NSMenuItem()
    private var accessStatusItem = NSMenuItem()
    private var accessPathItem = NSMenuItem()
    private var accessBundleItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupOverlay()
        setupPreviewPanel()
        setupHotKey()
        setupFnMonitor()
        bindPipeline()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = statusIdleTitle

        let menu = NSMenu()
        accessItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        revealItem = NSMenuItem(title: "Reveal App in Finder", action: #selector(revealApp), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")

        accessStatusItem = NSMenuItem(title: "Accessibility: unknown", action: nil, keyEquivalent: "")
        accessPathItem = NSMenuItem(title: "Path: unknown", action: nil, keyEquivalent: "")
        accessBundleItem = NSMenuItem(title: "Bundle: unknown", action: nil, keyEquivalent: "")

        accessItem.target = self
        revealItem.target = self
        quitItem.target = self

        accessStatusItem.isEnabled = false
        accessPathItem.isEnabled = false
        accessBundleItem.isEnabled = false

        menu.addItem(accessStatusItem)
        menu.addItem(accessPathItem)
        menu.addItem(accessBundleItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(accessItem)
        menu.addItem(revealItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)

        item.menu = menu
        menu.delegate = self
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
        fnMonitor.onFnDown = { [weak self] in
            self?.handleFnDown()
        }
        fnMonitor.onFnUp = { [weak self] in
            self?.handleFnUp()
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
        panel?.hide()
        previewModel.text = ""
        previewModel.state = .recording
        previewPanel?.show()
        Permissions.requestAccessibilityIfNeeded()
        updateAccessStatusItems()
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

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateAccessStatusItems()
    }

    private func updateAccessStatusItems() {
        let info = Permissions.accessibilityStatusInfo()
        accessStatusItem.title = "Accessibility: " + (info.trusted ? "trusted" : "denied")
        accessPathItem.title = "Path: \(info.path)"
        accessBundleItem.title = "Bundle: \(info.bundleID)"
    }
}
