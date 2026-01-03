import AppKit
import SwiftUI

@MainActor
final class ClipboardHistoryPanelController {
    static let shared = ClipboardHistoryPanelController()

    private let viewModel = ClipboardHistoryViewModel()
    private var panel: ClipboardHistoryPanel?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        createPanel()
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        viewModel.refresh(resetSelection: true)
        panel?.show()
        startKeyMonitor()
    }

    func hide() {
        panel?.hide()
        stopKeyMonitor()
        viewModel.clearQuery()
    }

    private func createPanel() {
        let view = ClipboardHistoryView(
            viewModel: viewModel,
            onInject: { [weak self] item in
                self?.viewModel.injectItem(item)
                self?.hide()
            }
        )
        panel = ClipboardHistoryPanel(rootView: view)
    }

    private func startKeyMonitor() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<ClipboardHistoryPanelController>.fromOpaque(refcon).takeUnretainedValue()
            if type != .keyDown {
                return Unmanaged.passUnretained(event)
            }
            return controller.handleEventTap(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        guard let eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func stopKeyMonitor() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEventTap(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard panel?.isVisible == true else { return Unmanaged.passUnretained(cgEvent) }
        guard let event = NSEvent(cgEvent: cgEvent) else { return Unmanaged.passUnretained(cgEvent) }

        let handled = handleKey(event)
        return handled ? nil : Unmanaged.passUnretained(cgEvent)
    }

    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }

        switch event.keyCode {
        case 53: // Esc
            hide()
            return true
        case 126: // Up
            viewModel.moveSelection(delta: -1)
            return true
        case 125: // Down
            viewModel.moveSelection(delta: 1)
            return true
        case 36: // Return
            viewModel.injectSelected()
            hide()
            return true
        case 51, 117: // Delete
            if event.modifierFlags.contains(.command) {
                viewModel.deleteSelected()
            } else {
                viewModel.deleteQueryBackward()
            }
            return true
        default:
            break
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) {
            if event.keyCode == 8 { // C
                viewModel.copySelected()
                return true
            }
            return true
        }
        if mods.contains(.control) || mods.contains(.option) {
            return true
        }

        guard let chars = event.characters, !chars.isEmpty else { return true }
        if chars == "\r" || chars == "\n" { return true }
        if chars.count == 1 {
            viewModel.appendQuery(chars)
        }
        return true
    }
}
