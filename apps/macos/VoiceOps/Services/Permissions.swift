import ApplicationServices
import AVFoundation

enum Permissions {
    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityIfNeeded() {
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
