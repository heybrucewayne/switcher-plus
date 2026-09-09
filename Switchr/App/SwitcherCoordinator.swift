import AppKit
import Combine
import SwiftUI

@MainActor
final class SwitcherCoordinator: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var selection = 0

    private let hotKey = HotKeyManager()
    private let windowManager = WindowManager()
    private let focusService = WindowFocusService()
    private let thumbnails = WindowThumbnailService()
    private var panel: SwitcherNSPanel?
    private var permissionPanel: NSPanel?

    func start() {
        hotKey.onAction = { [weak self] action in self?.handle(action) }
        hotKey.start()
    }

    func stop() {
        hotKey.stop()
        dismiss(cancelled: true)
    }

    func moveSelection(by amount: Int) {
        guard !windows.isEmpty else { return }
        selection = (selection + amount + windows.count) % windows.count
    }

    func selectAndFocus(_ window: WindowInfo) {
        guard let index = windows.firstIndex(of: window) else { return }
        selection = index
        dismiss(cancelled: false)
    }

    func dismiss(cancelled: Bool) {
        panel?.orderOut(nil)
        panel = nil
        let selected = windows.indices.contains(selection) ? windows[selection] : nil
        windows = []; selection = 0
        Task { await thumbnails.clear() }
        if !cancelled, let selected { focusService.focus(selected) }
    }

    func requestScreenRecording() { PermissionManager.requestScreenRecording() }
    func openAccessibilitySettings() { PermissionManager.promptForAccessibility() }

    private func handle(_ action: HotKeyManager.Action) {
        switch action {
        case .begin:
            guard PermissionManager.accessibilityGranted else { showPermissionPanel(); return }
            present()
        case .next: moveSelection(by: 1)
        case .previous: moveSelection(by: -1)
        case .commit: dismiss(cancelled: false)
        case .cancel: dismiss(cancelled: true)
        }
    }

    private func present() {
        windows = windowManager.windows()
        guard !windows.isEmpty else { return }
        selection = windows.count > 1 ? 1 : 0 // first Tab advances from the most recently listed window.
        let root = SwitcherPanel(coordinator: self, thumbnailService: thumbnails)
        let panel = SwitcherNSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: root)
        panel.setContentSize(NSSize(width: panelWidth, height: 290))
        panel.centerOnActiveScreen()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private var panelWidth: CGFloat {
        min(max(CGFloat(windows.count) * 184 + 44, 430), 1_180)
    }

    private func showPermissionPanel() {
        if let permissionPanel { permissionPanel.makeKeyAndOrderFront(nil); return }
        let root = PermissionView(coordinator: self)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 245), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: root)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        permissionPanel = panel
    }
}

private final class SwitcherNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func centerOnActiveScreen() {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }
        setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - frame.width / 2, y: screen.visibleFrame.midY - frame.height / 2))
    }
}
