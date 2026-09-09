import AppKit
import SwiftUI

struct WindowCard: View {
    let window: WindowInfo
    let isSelected: Bool
    let thumbnailService: WindowThumbnailService
    var cardWidth: CGFloat = 208
    @State private var thumbnail: CGImage?
    @State private var isHovered = false
    @State private var previewAttempted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var previewSlotHeight: CGFloat { cardWidth * 0.82 }
    private var appIcon: NSImage { NSRunningApplication(processIdentifier: window.ownerPID)?.icon ?? NSImage() }

    private var previewSize: CGSize {
        let sourceWidth = CGFloat(thumbnail?.width ?? Int(max(window.bounds.width, 1)))
        let sourceHeight = CGFloat(thumbnail?.height ?? Int(max(window.bounds.height, 1)))
        let aspectRatio = sourceWidth / max(sourceHeight, 1)
        // Equal visual area balances portrait utilities and wide document windows.
        // Extreme ratios still fit completely within the common preview slot.
        let area = cardWidth * previewSlotHeight * 0.66
        let width = sqrt(area * aspectRatio)
        let height = sqrt(area / aspectRatio)
        let fit = min(1, min(cardWidth / width, previewSlotHeight / height))
        return CGSize(width: width * fit, height: height * fit)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: previewSize.width, height: previewSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            minimizedBadge
                        }
                        .shadow(
                            color: .black.opacity(0.18),
                            radius: 5,
                            y: 3
                        )
                } else {
                    VStack(spacing: 8) {
                        Image(nsImage: appIcon).resizable().scaledToFit().frame(width: 40, height: 40)
                        Text(previewAttempted ? "Preview unavailable" : "Loading preview…")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: cardWidth, height: previewSlotHeight)

            Image(nsImage: appIcon)
                .resizable().scaledToFit().frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                .padding(.top, 12)
                .padding(.bottom, 7)
            Text(window.ownerName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if window.hasDistinctTitle {
                Text(window.displayTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.top, 3)
            } else {
                Color.clear.frame(height: 16)
            }
            Capsule()
                .fill(isSelected ? Color.accentColor : .clear)
                .frame(width: 24, height: 3)
                .padding(.top, 8)
        }
        .frame(width: cardWidth)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : (isHovered ? Color.primary.opacity(0.04) : .clear))
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .task(id: window.id) {
            repeat {
                let image = await thumbnailService.image(for: window)
                guard !Task.isCancelled else { return }
                thumbnail = image
                previewAttempted = true
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            } while !Task.isCancelled
        }
    }

    @ViewBuilder
    private var minimizedBadge: some View {
        if window.isMinimized {
            Image(systemName: "minus.rectangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(5)
                .background(.regularMaterial, in: Capsule())
                .padding(7)
                .accessibilityLabel("Minimized")
        }
    }
}
