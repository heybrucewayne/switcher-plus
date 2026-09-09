import SwiftUI

struct PermissionView: View {
    let coordinator: SwitcherCoordinator

    @State private var accessibilityGranted = PermissionManager.accessibilityGranted
    @State private var screenRecordingGranted = PermissionManager.screenRecordingGranted

    private var allPermissionsGranted: Bool {
        accessibilityGranted && screenRecordingGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: allPermissionsGranted ? "checkmark.circle.fill" : "rectangle.3.group.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(allPermissionsGranted ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(allPermissionsGranted ? "Switcher is ready" : "Set up Switcher +")
                        .font(.title3.weight(.semibold))
                    Text(allPermissionsGranted ? "All permissions are enabled." : "Two macOS permissions keep switching fast and private.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            PermissionRow(
                title: "Accessibility",
                detail: "Receives Option–Tab and brings the selected window forward.",
                isGranted: accessibilityGranted,
                actionTitle: "Open Settings",
                action: coordinator.openAccessibilitySettings
            )
            PermissionRow(
                title: "Screen Recording",
                detail: "Allows live thumbnails of your open windows. Without it, titles and app icons still work.",
                isGranted: screenRecordingGranted,
                actionTitle: "Open Settings",
                action: coordinator.openScreenRecordingSettings
            )

            if allPermissionsGranted {
                Label("Tamam — Switcher kullanıma hazır.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.top, 2)
            }

            HStack {
                Spacer()
                Button(allPermissionsGranted ? "Done" : "Check Again") {
                    if allPermissionsGranted {
                        coordinator.dismissPermissionPanel()
                    } else {
                        refresh()
                    }
                }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500, height: 392)
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() {
        accessibilityGranted = PermissionManager.accessibilityGranted
        screenRecordingGranted = PermissionManager.screenRecordingGranted
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isGranted ? .green : .secondary)
                .font(.system(size: 18))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !isGranted {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Text("On").font(.caption.weight(.medium)).foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
