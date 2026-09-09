import AppKit
import Combine
import SwiftUI
import OSLog

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
    private let logger = Logger(subsystem: "com.switchr.app", category: "Coordinator")
    private var permissionTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    func start() {
        hotKey.onAction = { [weak self] action in self?.handle(action) }
        hotKey.start()
        logger.notice("Startup accessibility=\(PermissionManager.accessibilityGranted) listener=\(self.hotKey.isRunning)")
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                // PermissionView polls both settings and shows the ready state;
                // keep it open until the user dismisses the confirmation.
            }
        }
        previewTask = Task { [thumbnails] in
            while !Task.isCancelled {
                await thumbnails.refreshVisibleWindows()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    func stop() {
        permissionTask?.cancel()
        permissionTask = nil
        hotKey.stop()
        previewTask?.cancel()
        previewTask = nil
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
        hotKey.resetSession()
        logger.notice("Switcher dismissed cancelled=\(cancelled)")
        panel?.orderOut(nil)
        panel = nil
        let selected = windows.indices.contains(selection) ? windows[selection] : nil
        windows = []; selection = 0

        if !cancelled, let selected { focusService.focus(selected, element: windowManager.elements[selected.id]) }
    }

    func requestScreenRecording() {
        dismiss(cancelled: true)
        PermissionManager.requestScreenRecording()
    }
    func openAccessibilitySettings() {
        PermissionManager.promptForAccessibility()
        PermissionManager.openAccessibilitySettings()
    }
    func openScreenRecordingSettings() { PermissionManager.openScreenRecordingSettings() }
    func dismissPermissionPanel() {
        permissionPanel?.close()
        permissionPanel = nil
    }

    func presentPermissionIfNeeded() {
        guard !PermissionManager.accessibilityGranted || !PermissionManager.screenRecordingGranted else { return }
        showPermissionPanel()
    }

    private func handle(_ action: HotKeyManager.Action) {
        switch action {
        case .begin:
            guard PermissionManager.accessibilityGranted else { hotKey.resetSession(); showPermissionPanel(); return }
            present()
        case .next: moveSelection(by: 1)
        case .previous:
            if panel == nil { present(); selection = max(0, windows.count - 1) }
            else { moveSelection(by: -1) }
        case .commit: dismiss(cancelled: false)
        case .cancel: dismiss(cancelled: true)
        }
    }

    private func present() {
        windows = windowManager.windows()
        logger.notice("Switcher opened with \(self.windows.count) windows")
        guard !windows.isEmpty else { hotKey.resetSession(); return }
        selection = windows.count > 1 ? 1 : 0 // first Tab advances from the most recently listed window.
        let root = SwitcherPanel(coordinator: self, thumbnailService: thumbnails)
        let panel = SwitcherNSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = ClickThroughHostingView(rootView: root)
        panel.setContentSize(NSSize(width: gridLayout.width, height: gridLayout.height))
        panel.centerOnActiveScreen()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    var gridLayout: SwitcherGridLayout {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        return SwitcherGridLayout(count: windows.count, screen: screen?.visibleFrame.size ?? CGSize(width: 1280, height: 800), permissionFooter: !PermissionManager.screenRecordingGranted)
    }

    var cardWidth: CGFloat { gridLayout.cardWidth }

    func moveRow(by amount: Int) {
        guard !windows.isEmpty else { return }
        selection = min(windows.count - 1, max(0, selection + amount * gridLayout.columns))
    }

    private func showPermissionPanel() {
        if let permissionPanel { permissionPanel.makeKeyAndOrderFront(nil); return }
        let root = PermissionView(coordinator: self)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 392), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
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

private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
