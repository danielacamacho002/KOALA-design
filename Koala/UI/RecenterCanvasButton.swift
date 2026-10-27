//
//  RecenterCanvasButton.swift
//  Koala
//

import SwiftUI

struct RecenterCanvasButton: View {
    var action: () -> Void
    /// When set, the scope icon turns white once it leaves the canvas sheet.
    var document: KoalaDocument?
    /// Top-left of this chrome overlay, in canvas-view coordinates.
    var overlayOrigin: CGPoint

    init(
        document: KoalaDocument? = nil,
        overlayOrigin: CGPoint = .zero,
        action: @escaping () -> Void
    ) {
        self.action = action
        self.document = document
        self.overlayOrigin = overlayOrigin
    }

    var body: some View {
        if let document {
            let sheet = CanvasIconContrast.sheetRect(
                viewport: document.viewport,
                canvasSize: document.settings.canvasSize,
                overlayOrigin: overlayOrigin
            )
            CanvasContrastTint(canvasRect: sheet) { overCanvas in
                button(
                    foreground: CanvasIconContrast.iconColor(isOverCanvas: overCanvas, onCanvasOpacity: 0.88),
                    wash: CanvasIconContrast.washColor(isOverCanvas: overCanvas)
                )
            }
        } else {
            button(
                foreground: Color.primary.opacity(0.88),
                wash: Color.primary.opacity(0.05)
            )
        }
    }

    private func button(foreground: Color, wash: Color) -> some View {
        Button(action: action) {
            Image(systemName: "scope")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(foreground)
                .background {
                    Circle()
                        .fill(wash)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter")
    }
}
