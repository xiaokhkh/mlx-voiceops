import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    init(rootView: some View) {
        let hosting = NSHostingView(rootView: rootView)
        let rect = NSRect(x: 0, y: 0, width: 360, height: 180)
        super.init(contentRect: rect, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, Numpad Enter
            onSubmit?()
        case 53: // Escape
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }

    func show() {
        positionTopCenter()
        makeKeyAndOrderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }

    private func positionTopCenter() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = self.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - 40
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
