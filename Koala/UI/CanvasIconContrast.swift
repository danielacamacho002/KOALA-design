//
//  CanvasIconContrast.swift
//  Koala
//

import SwiftUI

/// Named space covering the design chrome (the area below the toolbar).
/// Icon frames measured here line up with `overlayOrigin` passed from the editor.
enum CanvasOverlayCoordinateSpace {
    static let name = "canvasOverlay"
}

/// Picks black or white for chrome icons that float over the canvas sheet
/// and the dark pasteboard around it.
enum CanvasIconContrast {
    static func iconColor(isOverCanvas: Bool, onCanvasOpacity: CGFloat = 0.72) -> Color {
        if isOverCanvas {
            return Color.black.opacity(onCanvasOpacity)
        }
        return Color.white.opacity(0.92)
    }

    static func washColor(isOverCanvas: Bool) -> Color {
        (isOverCanvas ? Color.black : Color.white).opacity(0.05)
    }

    /// Canvas sheet mapped into the design chrome's coordinate space.
    static func sheetRect(
        viewport: ViewportTransform,
        canvasSize: CGSize,
        overlayOrigin: CGPoint
    ) -> CGRect {
        let viewRect = GridRenderer.canvasRectInView(viewport: viewport, canvasSize: canvasSize)
        guard !viewRect.isNull, !viewRect.isEmpty else { return .null }
        return viewRect.offsetBy(dx: -overlayOrigin.x, dy: -overlayOrigin.y)
    }

    /// True when the icon's center sits on the sheet. Unmeasured frames stay
    /// dark so the fitted canvas (sheet larger than the view) doesn't flash white.
    static func isOverCanvas(frame: CGRect, canvasRect: CGRect) -> Bool {
        guard frame.width > 1, frame.height > 1,
              !canvasRect.isNull, !canvasRect.isEmpty else {
            return true
        }
        return canvasRect.contains(CGPoint(x: frame.midX, y: frame.midY))
    }
}

/// Reports whether the modified view's center lies on the canvas sheet.
struct CanvasContrastTint<Content: View>: View {
    var canvasRect: CGRect
    @ViewBuilder var content: (Bool) -> Content

    @State private var frame: CGRect = .zero

    private var isOverCanvas: Bool {
        CanvasIconContrast.isOverCanvas(frame: frame, canvasRect: canvasRect)
    }

    var body: some View {
        content(isOverCanvas)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: CanvasOverlayFrameKey.self,
                            value: proxy.frame(in: .named(CanvasOverlayCoordinateSpace.name))
                        )
                }
                .allowsHitTesting(false)
            }
            .onPreferenceChange(CanvasOverlayFrameKey.self) { newFrame in
                publish(newFrame)
            }
    }

    private func publish(_ next: CGRect) {
        guard next.width > 1, next.height > 1 else { return }
        let delta = abs(next.midX - frame.midX) + abs(next.midY - frame.midY)
            + abs(next.width - frame.width) + abs(next.height - frame.height)
        guard delta > 0.5 else { return }
        frame = next
    }
}

private struct CanvasOverlayFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}
