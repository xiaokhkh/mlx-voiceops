import Cocoa
import ApplicationServices

final class InputInjector {
    func insertViaPaste(_ text: String) -> Bool {
        guard Permissions.hasAccessibility() else { return false }

        let pb = NSPasteboard.general
        let backup = pb.pasteboardItems ?? []
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let kV: CGKeyCode = 9 // US layout 'v'

        func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
            if let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) {
                e.flags = flags
                e.post(tap: .cghidEventTap)
            }
        }

        post(kV, down: true, flags: [.maskCommand])
        post(kV, down: false, flags: [.maskCommand])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pb.clearContents()
            for item in backup { pb.writeObjects([item]) }
        }
        return true
    }
}
