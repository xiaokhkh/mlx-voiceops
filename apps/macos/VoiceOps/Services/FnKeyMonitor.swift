import AppKit
import ApplicationServices

final class FnKeyMonitor {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?
    var onFnSpace: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isFnDown = false

    private func dispatchAction(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    func start() {
        guard eventTap == nil, globalMonitor == nil, localMonitor == nil else { return }
        if !startEventTap() {
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
        isFnDown = false
    }

    private func startEventTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
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
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleFallbackEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            let shouldSwallow = self.handleFallbackEvent(event)
            return shouldSwallow ? nil : event
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

        if type == .flagsChanged {
            handleFnState(fnNow: fnNow)
        } else if type == .keyDown, fnNow {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if keyCode == 49, !isRepeat {
                dispatchAction { [weak self] in
                    self?.onFnSpace?()
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
            handleFnState(fnNow: fnNow)
        case .keyDown:
            guard fnNow, event.keyCode == 49, !event.isARepeat else { return false }
            dispatchAction { [weak self] in
                self?.onFnSpace?()
            }
            return true
        default:
            break
        }
        return false
    }

    private func handleFnState(fnNow: Bool) {
        if fnNow && !isFnDown {
            isFnDown = true
            dispatchAction { [weak self] in
                self?.onFnDown?()
            }
        } else if !fnNow && isFnDown {
            isFnDown = false
            dispatchAction { [weak self] in
                self?.onFnUp?()
            }
        }
    }
}
