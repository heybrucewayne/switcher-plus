import CoreGraphics
import ApplicationServices
import OSLog

final class HotKeyManager: @unchecked Sendable {
    enum Action { case begin, next, previous, commit, cancel }
    var onAction: ((Action) -> Void)?

    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var showingSwitcher = false
    private var maintenanceTimer: Timer?
    private var sessionStarted = Date.distantPast
    private let logger = Logger(subsystem: "com.switchr.app", category: "HotKey")

    var isRunning: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {
        if maintenanceTimer == nil {
            maintenanceTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.maintain() }
            CFRunLoopAddTimer(CFRunLoopGetMain(), maintenanceTimer, .commonModes)
        }
        installTapIfNeeded()
    }

    private func installTapIfNeeded() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: Self.callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap else {
            logger.error("Could not create global event tap; Accessibility permission may be missing.")
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.notice("Option-Tab listener connected")
    }

    func resetSession() { showingSwitcher = false }

    func stop() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
        resetSession()
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; source = nil
    }

    private func maintain() {
        if eventTap == nil { installTapIfNeeded() }
        if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        // Nonactivating panels and permission dialogs can consume flagsChanged.
        // Read the actual session flags as a fallback, after the initial key event.
        if showingSwitcher, Date().timeIntervalSince(sessionStarted) > 0.15,
           !CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) {
            showingSwitcher = false
            onAction?(.commit)
        }
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
        if type == .keyDown, showingSwitcher, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            showingSwitcher = false
            DispatchQueue.main.async { self.onAction?(.cancel) }
            return nil
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
        if !showingSwitcher { sessionStarted = Date() }
        showingSwitcher = true
        DispatchQueue.main.async { self.onAction?(action) }
        return nil
    }
}
