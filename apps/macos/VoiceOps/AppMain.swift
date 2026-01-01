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
    private var statusItem: NSStatusItem?
    private var panel: OverlayPanel?
    private var hotKey: HotKeyService?
    private var cancellables = Set<AnyCancellable>()

    private let pipeline = PipelineController()
    private var toggleItem = NSMenuItem()
    private var insertItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupOverlay()
        setupHotKey()
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
