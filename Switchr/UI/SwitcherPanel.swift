import SwiftUI

struct SwitcherPanel: View {
    @ObservedObject var coordinator: SwitcherCoordinator
    let thumbnailService: WindowThumbnailService
    @State private var hasScreenPermission = PermissionManager.screenRecordingGranted

    var body: some View {
        VStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(coordinator.cardWidth + 16), spacing: 12), count: coordinator.gridLayout.columns), spacing: 16) {
                        ForEach(Array(coordinator.windows.enumerated()), id: \.element.id) { index, window in
                            Button { coordinator.selectAndFocus(window) } label: {
                                WindowCard(window: window, isSelected: index == coordinator.selection, thumbnailService: thumbnailService, cardWidth: coordinator.cardWidth)
                            }
                            .frame(height: coordinator.gridLayout.rowHeight)
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .id(window.id)
                            .accessibilityLabel("\(window.ownerName), \(window.displayTitle)\(window.isMinimized ? ", minimized" : "")")
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if coordinator.windows.indices.contains(coordinator.selection) {
                        proxy.scrollTo(coordinator.windows[coordinator.selection].id, anchor: .center)
                    }
                }
                .onChange(of: coordinator.selection) { _, selection in
                    guard coordinator.windows.indices.contains(selection) else { return }
                    proxy.scrollTo(coordinator.windows[selection].id, anchor: .center)
                }
            }
            if !hasScreenPermission {
                Button("Enable window previews — Screen Recording permission") {
                    coordinator.requestScreenRecording()
                    hasScreenPermission = PermissionManager.screenRecordingGranted
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(LiquidGlassPanel())
        .padding(24)
        .onKeyPress(.leftArrow) { coordinator.moveSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { coordinator.moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { coordinator.moveRow(by: -1); return .handled }
        .onKeyPress(.downArrow) { coordinator.moveRow(by: 1); return .handled }
        .onKeyPress(.escape) { coordinator.dismiss(cancelled: true); return .handled }
    }
}

private struct LiquidGlassPanel: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            ZStack {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular, in: shape)
                content
            }
                .clipShape(shape)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial)
                content
            }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(0.30), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        }
    }
}
