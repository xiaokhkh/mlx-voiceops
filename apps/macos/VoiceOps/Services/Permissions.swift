import ApplicationServices
import AVFoundation
import Foundation

enum Permissions {
    private static var didPromptAccessibility = false

    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func accessibilityStatusInfo() -> (trusted: Bool, bundleID: String, path: String) {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let path = Bundle.main.bundlePath
        return (AXIsProcessTrusted(), bundleID, path)
    }

    static func accessibilityStatus() -> String {
        let info = accessibilityStatusInfo()
        let pid = ProcessInfo.processInfo.processIdentifier
        return "trusted=\(info.trusted) bundle_id=\(info.bundleID) pid=\(pid) path=\(info.path)"
    }

    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        guard !didPromptAccessibility else { return }
        didPromptAccessibility = true
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options: NSDictionary = [key: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophoneIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
}
