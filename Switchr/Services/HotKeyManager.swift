import CoreGraphics
import OSLog

final class HotKeyManager: @unchecked Sendable {
    enum Action { case begin, next, previous, commit, cancel }
    var onAction: ((Action) -> Void)?

    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var showingSwitcher = false
    private let logger = Logger(subsystem: "com.switchr.app", category: "HotKey")

    func start() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: Self.callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap else {
            logger.error("Could not create global event tap; Accessibility permission may be missing.")
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; source = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
        return manager.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        if type == .flagsChanged, !flags.contains(.maskAlternate), showingSwitcher {
            showingSwitcher = false; DispatchQueue.main.async { self.onAction?(.commit) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 48, flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }
        let action: Action = flags.contains(.maskShift) ? .previous : (showingSwitcher ? .next : .begin)
        showingSwitcher = true
        DispatchQueue.main.async { self.onAction?(action) }
        return nil
    }
}
