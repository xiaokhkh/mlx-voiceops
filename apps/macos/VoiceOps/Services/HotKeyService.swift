import Carbon
import Foundation

final class HotKeyService {
    private let handler: () -> Void
    private let signature: OSType = OSType(UInt32(truncatingIfNeeded: 0x564F5053)) // 'VOPS'
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) throws {
        self.handler = handler

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return noErr }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if status == noErr && hotKeyID.signature == service.signature {
                    service.handler()
                }

                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandler
        )

        guard installStatus == noErr else {
            throw NSError(domain: "HotKeyService", code: Int(installStatus))
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            throw NSError(domain: "HotKeyService", code: Int(registerStatus))
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

struct HotKeyKey: Identifiable, Hashable {
    let keyCode: UInt32
    let label: String

    var id: UInt32 { keyCode }
}

struct HotKeyPreference: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let keyCodeDefaultsKey = "hotkeyKeyCode"
    static let modifiersDefaultsKey = "hotkeyModifiers"
    static let defaultValue = HotKeyPreference(
        keyCode: UInt32(kVK_Function),
        modifiers: UInt32(cmdKey)
    )

    static let supportedKeys: [HotKeyKey] = [
        HotKeyKey(keyCode: UInt32(kVK_Function), label: "Fn"),
        HotKeyKey(keyCode: UInt32(kVK_Space), label: "Space"),
        HotKeyKey(keyCode: UInt32(kVK_Return), label: "Return"),
        HotKeyKey(keyCode: UInt32(kVK_Tab), label: "Tab"),
        HotKeyKey(keyCode: UInt32(kVK_Escape), label: "Escape"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_A), label: "A"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_B), label: "B"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_C), label: "C"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_D), label: "D"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_E), label: "E"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_F), label: "F"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_G), label: "G"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_H), label: "H"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_I), label: "I"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_J), label: "J"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_K), label: "K"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_L), label: "L"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_M), label: "M"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_N), label: "N"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_O), label: "O"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_P), label: "P"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_Q), label: "Q"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_R), label: "R"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_S), label: "S"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_T), label: "T"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_U), label: "U"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_V), label: "V"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_W), label: "W"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_X), label: "X"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_Y), label: "Y"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_Z), label: "Z"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_0), label: "0"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_1), label: "1"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_2), label: "2"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_3), label: "3"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_4), label: "4"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_5), label: "5"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_6), label: "6"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_7), label: "7"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_8), label: "8"),
        HotKeyKey(keyCode: UInt32(kVK_ANSI_9), label: "9"),
        HotKeyKey(keyCode: UInt32(kVK_LeftArrow), label: "Left Arrow"),
        HotKeyKey(keyCode: UInt32(kVK_RightArrow), label: "Right Arrow"),
        HotKeyKey(keyCode: UInt32(kVK_UpArrow), label: "Up Arrow"),
        HotKeyKey(keyCode: UInt32(kVK_DownArrow), label: "Down Arrow"),
        HotKeyKey(keyCode: UInt32(kVK_Home), label: "Home"),
        HotKeyKey(keyCode: UInt32(kVK_End), label: "End"),
        HotKeyKey(keyCode: UInt32(kVK_PageUp), label: "Page Up"),
        HotKeyKey(keyCode: UInt32(kVK_PageDown), label: "Page Down"),
        HotKeyKey(keyCode: UInt32(kVK_Delete), label: "Delete"),
        HotKeyKey(keyCode: UInt32(kVK_ForwardDelete), label: "Forward Delete"),
        HotKeyKey(keyCode: UInt32(kVK_F1), label: "F1"),
        HotKeyKey(keyCode: UInt32(kVK_F2), label: "F2"),
        HotKeyKey(keyCode: UInt32(kVK_F3), label: "F3"),
        HotKeyKey(keyCode: UInt32(kVK_F4), label: "F4"),
        HotKeyKey(keyCode: UInt32(kVK_F5), label: "F5"),
        HotKeyKey(keyCode: UInt32(kVK_F6), label: "F6"),
        HotKeyKey(keyCode: UInt32(kVK_F7), label: "F7"),
        HotKeyKey(keyCode: UInt32(kVK_F8), label: "F8"),
        HotKeyKey(keyCode: UInt32(kVK_F9), label: "F9"),
        HotKeyKey(keyCode: UInt32(kVK_F10), label: "F10"),
        HotKeyKey(keyCode: UInt32(kVK_F11), label: "F11"),
        HotKeyKey(keyCode: UInt32(kVK_F12), label: "F12"),
    ]

    static let supportedKeyCodes = Set(supportedKeys.map(\.keyCode))

    static func load() -> HotKeyPreference {
        let defaults = UserDefaults.standard
        let keyCodeValue = defaults.object(forKey: keyCodeDefaultsKey) as? Int
        let modifiersValue = defaults.object(forKey: modifiersDefaultsKey) as? Int
        let keyCode = UInt32(keyCodeValue ?? Int(defaultValue.keyCode))
        let modifiers = UInt32(modifiersValue ?? Int(defaultValue.modifiers))
        let candidate = HotKeyPreference(keyCode: keyCode, modifiers: modifiers)
        return candidate.isValid ? candidate : defaultValue
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(Int(modifiers), forKey: Self.modifiersDefaultsKey)
    }

    var isValid: Bool {
        modifiers != 0
    }

    var displayString: String {
        Self.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Command")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Option")
        }
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Control")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        let keyLabel = keyLabel(for: keyCode)
        parts.append(keyLabel)
        return parts.joined(separator: "+")
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        supportedKeys.first(where: { $0.keyCode == keyCode })?.label ?? "KeyCode \(keyCode)"
    }
}

struct ActivationKeyPreference: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let keyCodeDefaultsKey = "activationKeyCode"
    static let modifiersDefaultsKey = "activationKeyModifiers"
    static let defaultValue = ActivationKeyPreference(
        keyCode: UInt32(kVK_Function),
        modifiers: 0
    )

    static func load() -> ActivationKeyPreference {
        let defaults = UserDefaults.standard
        let keyCodeValue = defaults.object(forKey: keyCodeDefaultsKey) as? Int
        let modifiersValue = defaults.object(forKey: modifiersDefaultsKey) as? Int
        let keyCode = UInt32(keyCodeValue ?? Int(defaultValue.keyCode))
        let modifiers = UInt32(modifiersValue ?? Int(defaultValue.modifiers))
        let candidate = ActivationKeyPreference(keyCode: keyCode, modifiers: modifiers)
        return candidate.isValid ? candidate : defaultValue
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(Int(modifiers), forKey: Self.modifiersDefaultsKey)
    }

    var isValid: Bool {
        true
    }

    var displayString: String {
        HotKeyPreference.displayString(keyCode: keyCode, modifiers: modifiers)
    }
}
