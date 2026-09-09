import SwiftUI

struct PermissionView: View {
    let coordinator: SwitcherCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 31)).foregroundStyle(.tint)
            Text("Switchr needs Accessibility permission")
                .font(.title3.weight(.semibold))
            Text("This lets Switchr receive Option–Tab and bring the window you choose to the front. It stays local to your Mac.")
                .font(.body).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Open System Settings") { coordinator.openAccessibilitySettings() }.keyboardShortcut(.defaultAction) }
        }
        .padding(28).frame(width: 410, height: 245)
    }
}
