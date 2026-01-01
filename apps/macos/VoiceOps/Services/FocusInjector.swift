import Cocoa
import ApplicationServices

final class FocusInjector {
    struct FocusTarget {
        let element: AXUIElement
    }

    private struct FocusSnapshot {
        let element: AXUIElement
        let value: String
        let range: CFRange?
    }

    func captureFocusTarget() -> FocusTarget? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let focusStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success, let focused else { return nil }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return FocusTarget(element: focused as! AXUIElement)
    }

    func inject(_ text: String, target: FocusTarget? = nil, restoreClipboard: Bool = false) -> Bool {
        guard !text.isEmpty else { return true }

        guard Permissions.hasAccessibility() else {
            print("[inject] access_denied \(Permissions.accessibilityStatus())")
            Permissions.requestAccessibilityIfNeeded()
            return false
        }

        if let target {
            guard let snapshot = snapshot(for: target) else {
                print("[inject] target_snapshot_failed")
                return false
            }
            let didInsert = insertViaAX(text: text, snapshot: snapshot)
            if !didInsert {
                print("[inject] target_ax_failed")
            }
            return didInsert
        }

        let pb = NSPasteboard.general
        let backup = restoreClipboard ? (pb.pasteboardItems ?? []) : []
        pb.clearContents()
        let didSet = pb.setString(text, forType: .string)
        if !didSet {
            print("[inject] pasteboard_set_failed")
        }

        let snapshot = snapshotForCurrentFocus()

        usleep(25_000)
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            print("[inject] event_source_failed")
            return fallbackInsert(text: text, snapshot: snapshot)
        }
        let cmdKey: CGKeyCode = 55 // Left Command
        let vKey: CGKeyCode = 9 // US layout 'v'

        func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) -> Bool {
            guard let event = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else {
                return false
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            return true
        }

        let cmdDown = post(cmdKey, down: true, flags: [.maskCommand])
        let vDown = post(vKey, down: true, flags: [.maskCommand])
        let vUp = post(vKey, down: false, flags: [.maskCommand])
        let cmdUp = post(cmdKey, down: false, flags: [])
        if !(cmdDown && vDown && vUp && cmdUp) {
            print("[inject] event_post_failed")
            return fallbackInsert(text: text, snapshot: snapshot)
        }

        if let snapshot {
            if verifyPasteApplied(text: text, snapshot: snapshot) {
                return true
            }
            if insertViaAX(text: text, snapshot: snapshot) {
                return true
            }
        }

        if restoreClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                pb.clearContents()
                for item in backup { pb.writeObjects([item]) }
            }
        }

        return true
    }

    private func fallbackInsert(text: String, snapshot: FocusSnapshot?) -> Bool {
        if let snapshot, insertViaAX(text: text, snapshot: snapshot) {
            return true
        }
        return insertViaTyping(text)
    }

    private func snapshotForCurrentFocus() -> FocusSnapshot? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let focusStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success, let focused else { return nil }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var valueObj: AnyObject?
        let valueStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueObj
        )
        guard valueStatus == .success, let value = valueObj as? String else { return nil }

        var rangeObj: AnyObject?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeObj
        )
        var range: CFRange?
        if rangeStatus == .success, let rangeObj {
            if CFGetTypeID(rangeObj) == AXValueGetTypeID() {
                let axValue = rangeObj as! AXValue
                var cfRange = CFRange()
                if AXValueGetValue(axValue, .cfRange, &cfRange) {
                    range = cfRange
                }
            }
        }

        return FocusSnapshot(element: element, value: value, range: range)
    }

    private func snapshot(for target: FocusTarget) -> FocusSnapshot? {
        var valueObj: AnyObject?
        let valueStatus = AXUIElementCopyAttributeValue(
            target.element,
            kAXValueAttribute as CFString,
            &valueObj
        )
        guard valueStatus == .success, let value = valueObj as? String else { return nil }

        var rangeObj: AnyObject?
        let rangeStatus = AXUIElementCopyAttributeValue(
            target.element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeObj
        )
        var range: CFRange?
        if rangeStatus == .success, let rangeObj {
            if CFGetTypeID(rangeObj) == AXValueGetTypeID() {
                let axValue = rangeObj as! AXValue
                var cfRange = CFRange()
                if AXValueGetValue(axValue, .cfRange, &cfRange) {
                    range = cfRange
                }
            }
        }

        return FocusSnapshot(element: target.element, value: value, range: range)
    }

    private func verifyPasteApplied(text: String, snapshot: FocusSnapshot) -> Bool {
        guard let expected = expectedValue(text: text, snapshot: snapshot) else { return false }
        usleep(60_000)
        var valueObj: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            snapshot.element,
            kAXValueAttribute as CFString,
            &valueObj
        )
        guard status == .success, let value = valueObj as? String else { return false }
        return value == expected
    }

    private func insertViaAX(text: String, snapshot: FocusSnapshot) -> Bool {
        guard let expected = expectedValue(text: text, snapshot: snapshot) else { return false }
        let setStatus = AXUIElementSetAttributeValue(
            snapshot.element,
            kAXValueAttribute as CFString,
            expected as CFTypeRef
        )
        guard setStatus == .success else { return false }

        if var range = snapshot.range {
            range.location += text.count
            range.length = 0
            if let axRange = AXValueCreate(.cfRange, &range) {
                _ = AXUIElementSetAttributeValue(
                    snapshot.element,
                    kAXSelectedTextRangeAttribute as CFString,
                    axRange
                )
            }
        }
        return true
    }

    private func expectedValue(text: String, snapshot: FocusSnapshot) -> String? {
        guard let range = snapshot.range else { return nil }
        let nsValue = snapshot.value as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        return nsValue.replacingCharacters(in: nsRange, with: text)
    }

    private func insertViaTyping(_ text: String) -> Bool {
        let src = CGEventSource(stateID: .combinedSessionState)
        let chars = Array(text.utf16)

        var didPost = false
        chars.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: base)
                keyUp.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: base)
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
                didPost = true
            }
        }
        if !didPost {
            print("[inject] typing_failed")
        }
        return didPost
    }
}
