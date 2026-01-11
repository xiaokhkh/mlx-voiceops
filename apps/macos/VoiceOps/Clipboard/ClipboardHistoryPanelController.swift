import AppKit
import SwiftUI

@MainActor
final class ClipboardHistoryPanelController {
    static let shared = ClipboardHistoryPanelController()

    private let viewModel = ClipboardHistoryViewModel()
    private var panel: ClipboardHistoryPanel?
    private var previewPanel: ImagePreviewPanel?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previewedItemID: UUID?

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
        hidePreview()
        startKeyMonitor()
    }

    func hide() {
        panel?.hide()
        stopKeyMonitor()
        hidePreview()
        viewModel.clearQuery()
    }

    private func createPanel() {
        let view = ClipboardHistoryView(
            viewModel: viewModel,
            onInject: { [weak self] item in
                self?.viewModel.activateItem(item)
                self?.hide()
            },
            onHoverImage: { [weak self] item in
                self?.handleHover(item: item)
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
            viewModel.activateSelected()
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

    private func handleHover(item: ClipboardItem?) {
        guard let item, let image = viewModel.previewImage(for: item) else {
            hidePreview()
            return
        }
        if previewedItemID == item.id {
            return
        }
        previewedItemID = item.id
        showPreview(image: image)
    }

    private func showPreview(image: NSImage) {
        if previewPanel == nil {
            previewPanel = ImagePreviewPanel(rootView: ImagePreviewView(image: image))
        } else {
            previewPanel?.update(image: image)
        }
        previewPanel?.show(at: NSEvent.mouseLocation)
    }

    private func hidePreview() {
        previewedItemID = nil
        previewPanel?.hide()
    }
}

private final class ImagePreviewPanel: NSPanel {
    private let hosting: NSHostingView<ImagePreviewView>

    init(rootView: ImagePreviewView) {
        hosting = NSHostingView(rootView: rootView)
        let rect = NSRect(x: 0, y: 0, width: 280, height: 200)
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true

        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(image: NSImage) {
        hosting.rootView = ImagePreviewView(image: image)
    }

    func show(at point: NSPoint) {
        position(near: point)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    private func position(near point: NSPoint) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        var x = point.x + 16
        var y = point.y - size.height - 16
        if x + size.width > visible.maxX {
            x = visible.maxX - size.width - 8
        }
        if x < visible.minX {
            x = visible.minX + 8
        }
        if y < visible.minY {
            y = point.y + 16
        }
        if y + size.height > visible.maxY {
            y = visible.maxY - size.height - 8
        }
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct ImagePreviewView: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 280, height: 200)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12))
            )
    }
}
