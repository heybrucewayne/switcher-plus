import AppKit
import SwiftUI

struct WindowCard: View {
    let window: WindowInfo
    let isSelected: Bool
    let thumbnailService: WindowThumbnailService
    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(spacing: 9) {
            preview
                .frame(width: 154, height: 104)
            HStack(spacing: 6) {
                Image(nsImage: NSRunningApplication(processIdentifier: window.ownerPID)?.icon ?? NSImage())
                    .resizable().scaledToFit().frame(width: 18, height: 18)
                Text(window.ownerName).lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            Text(window.displayTitle).lineLimit(1).truncationMode(.tail)
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(width: 166, height: 238)
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isSelected ? Color.accentColor.opacity(0.78) : .clear, lineWidth: 1) }
        .shadow(color: isSelected ? Color.accentColor.opacity(0.18) : .clear, radius: 12, y: 6)
        .scaleEffect(isSelected ? 1.025 : 0.97)
        .opacity(isSelected ? 1 : 0.70)
        .animation(.spring(response: 0.18, dampingFraction: 0.84), value: isSelected)
        .task(id: window.id) { thumbnail = await thumbnailService.image(for: window.id) }
    }

    @ViewBuilder private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable().scaledToFill().clipped()
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.quaternary)
                Image(nsImage: NSRunningApplication(processIdentifier: window.ownerPID)?.icon ?? NSImage())
                    .resizable().scaledToFit().frame(width: 42, height: 42).opacity(0.8)
            }
        }
    }
}
