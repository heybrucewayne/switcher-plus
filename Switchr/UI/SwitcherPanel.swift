import SwiftUI

struct SwitcherPanel: View {
    @ObservedObject var coordinator: SwitcherCoordinator
    let thumbnailService: WindowThumbnailService

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(coordinator.windows.enumerated()), id: \.element.id) { index, window in
                WindowCard(window: window, isSelected: index == coordinator.selection, thumbnailService: thumbnailService)
                    .onTapGesture { coordinator.selectAndFocus(window) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.28), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
        .onKeyPress(.tab) {
            coordinator.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.leftArrow) { coordinator.moveSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { coordinator.moveSelection(by: 1); return .handled }
        .onKeyPress(.escape) { coordinator.dismiss(cancelled: true); return .handled }
    }
}
