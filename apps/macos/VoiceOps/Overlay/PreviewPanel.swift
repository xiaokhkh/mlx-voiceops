import AppKit
import SwiftUI

final class PreviewPanel: NSPanel {
    init(rootView: some View) {
        let hosting = NSHostingView(rootView: rootView)
        let rect = NSRect(x: 0, y: 0, width: 360, height: 120)
        super.init(contentRect: rect, styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)

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

    func show() {
        positionBottomCenter()
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = self.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 80
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
