import AppKit
import ApplicationServices
import Carbon

final class FnKeyMonitor {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?
    var onFnSpace: (() -> Void)?
    var onClipboardToggle: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isActivationDown = false
    private var isClipboardDown = false
    private let fnKeyCode: CGKeyCode = CGKeyCode(kVK_Function)
    private var activationKeyCode: CGKeyCode = CGKeyCode(kVK_Function)
    private var activationModifiers: UInt32 = 0
    private var clipboardKeyCode: CGKeyCode = CGKeyCode(kVK_Function)
    private var clipboardModifiers: UInt32 = UInt32(cmdKey)

    private var activationUsesFn: Bool {
        activationKeyCode == fnKeyCode && activationModifiers == 0
    }

    private var clipboardUsesFn: Bool {
        clipboardKeyCode == fnKeyCode
    }

    private func dispatchAction(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    func start() {
        ensureEventTap()
        if eventTap == nil {
            startFallbackMonitors()
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        runLoopSource = nil
        eventTap = nil
        globalMonitor = nil
        localMonitor = nil
        isActivationDown = false
        isClipboardDown = false
    }

    func updateActivationKey(keyCode: UInt32, modifiers: UInt32) {
        activationKeyCode = CGKeyCode(keyCode)
        activationModifiers = modifiers
        isActivationDown = false
    }

    func updateClipboardShortcut(keyCode: UInt32, modifiers: UInt32) {
        clipboardKeyCode = CGKeyCode(keyCode)
        clipboardModifiers = modifiers
        isClipboardDown = false
    }

    func ensureEventTap() {
        guard eventTap == nil else { return }
        if !startEventTap() {
            startFallbackMonitors()
        }
    }

    private func startEventTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleEventTap(proxy: proxy, type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let eventTap else { return false }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func startFallbackMonitors() {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
                self?.handleFallbackEvent(event)
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
                guard let self else { return event }
                let shouldSwallow = self.handleFallbackEvent(event)
                return shouldSwallow ? nil : event
            }
        }
    }

    private func handleEventTap(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let fnNow = event.flags.contains(.maskSecondaryFn)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged {
            if clipboardUsesFn {
                handleClipboardFnCombo(fnNow: fnNow, flags: event.flags)
            }
            if keyCode == Int64(fnKeyCode) {
                if activationUsesFn {
                    handleFnActivationState(fnNow: fnNow)
                }
            }
        } else if type == .keyDown {
            if onClipboardToggle != nil, !clipboardUsesFn {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isRepeat, matchesClipboardShortcut(keyCode: keyCode, flags: event.flags) {
                    isClipboardDown = true
                    dispatchAction { [weak self] in
                        self?.onClipboardToggle?()
                    }
                    return nil
                }
            }
            if !activationUsesFn {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isRepeat, keyCode == Int64(activationKeyCode), matchesActivationModifiers(flags: event.flags) {
                    if !isActivationDown {
                        isActivationDown = true
                        dispatchAction { [weak self] in
                            self?.onFnDown?()
                        }
                    }
                    return nil
                }
            }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if keyCode == 49, !isRepeat, onFnSpace != nil {
                dispatchAction { [weak self] in
                    self?.onFnSpace?()
                }
                return nil
            }
        } else if type == .keyUp {
            if !clipboardUsesFn, isClipboardDown, keyCode == Int64(clipboardKeyCode) {
                isClipboardDown = false
                return nil
            }
            if !activationUsesFn, keyCode == Int64(activationKeyCode) {
                if isActivationDown {
                    isActivationDown = false
                    dispatchAction { [weak self] in
                        self?.onFnUp?()
                    }
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    @discardableResult
    private func handleFallbackEvent(_ event: NSEvent) -> Bool {
        let fnNow = event.modifierFlags.contains(.function)
        switch event.type {
        case .flagsChanged:
            if clipboardUsesFn {
                handleClipboardFnCombo(fnNow: fnNow, flags: event.modifierFlags)
            }
            if event.keyCode == fnKeyCode {
                if activationUsesFn {
                    handleFnActivationState(fnNow: fnNow)
                }
            }
        case .keyDown:
            if onClipboardToggle != nil, !clipboardUsesFn, !event.isARepeat,
               matchesClipboardShortcut(keyCode: event.keyCode, flags: event.modifierFlags)
            {
                isClipboardDown = true
                dispatchAction { [weak self] in
                    self?.onClipboardToggle?()
                }
                return true
            }
            if !activationUsesFn,
               !event.isARepeat,
               event.keyCode == activationKeyCode,
               matchesActivationModifiers(flags: event.modifierFlags)
            {
                if !isActivationDown {
                    isActivationDown = true
                    dispatchAction { [weak self] in
                        self?.onFnDown?()
                    }
                }
                return true
            }
            guard fnNow, event.keyCode == 49, !event.isARepeat else { return false }
            guard onFnSpace != nil else { return false }
            dispatchAction { [weak self] in
                self?.onFnSpace?()
            }
            return true
        case .keyUp:
            if !clipboardUsesFn, isClipboardDown, event.keyCode == clipboardKeyCode {
                isClipboardDown = false
                return true
            }
            if !activationUsesFn, event.keyCode == activationKeyCode {
                if isActivationDown {
                    isActivationDown = false
                    dispatchAction { [weak self] in
                        self?.onFnUp?()
                    }
                }
                return true
            }
            return true
        default:
            break
        }
        return false
    }

    private func handleClipboardFnCombo(fnNow: Bool, flags: CGEventFlags) {
        guard clipboardUsesFn, onClipboardToggle != nil else { return }
        let comboActive = fnNow && effectiveModifiers(from: flags) == clipboardModifiers
        if comboActive && !isClipboardDown {
            isClipboardDown = true
            dispatchAction { [weak self] in
                self?.onClipboardToggle?()
            }
            return
        }
        if !comboActive && isClipboardDown {
            isClipboardDown = false
        }
    }

    private func handleClipboardFnCombo(fnNow: Bool, flags: NSEvent.ModifierFlags) {
        guard clipboardUsesFn, onClipboardToggle != nil else { return }
        let comboActive = fnNow && effectiveModifiers(from: flags) == clipboardModifiers
        if comboActive && !isClipboardDown {
            isClipboardDown = true
            dispatchAction { [weak self] in
                self?.onClipboardToggle?()
            }
            return
        }
        if !comboActive && isClipboardDown {
            isClipboardDown = false
        }
    }

    private func handleFnActivationState(fnNow: Bool) {
        if fnNow && !isActivationDown {
            isActivationDown = true
            dispatchAction { [weak self] in
                self?.onFnDown?()
            }
        } else if !fnNow && isActivationDown {
            isActivationDown = false
            dispatchAction { [weak self] in
                self?.onFnUp?()
            }
        }
    }

    private func matchesActivationModifiers(flags: CGEventFlags) -> Bool {
        effectiveModifiers(from: flags) == activationModifiers
    }

    private func matchesActivationModifiers(flags: NSEvent.ModifierFlags) -> Bool {
        effectiveModifiers(from: flags) == activationModifiers
    }

    private func matchesClipboardShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == Int64(clipboardKeyCode) && effectiveModifiers(from: flags) == clipboardModifiers
    }

    private func matchesClipboardShortcut(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == clipboardKeyCode && effectiveModifiers(from: flags) == clipboardModifiers
    }

    private func effectiveModifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.maskAlternate) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.maskControl) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.maskShift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }

    private func effectiveModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }
}
