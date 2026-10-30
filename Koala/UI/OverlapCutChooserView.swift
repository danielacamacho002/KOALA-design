//
//  OverlapCutChooserView.swift
//  Koala
//

import SwiftUI

/// Plus, minus, and check for an armed overlap cut, plus a preview of the result.
/// Hit testing stays off; the canvas tap handler owns the chips.
struct OverlapCutChooserView: View {
    var document: KoalaDocument
    var baseID: UUID
    var cutterID: UUID
    var tapPoint: CGPoint

    var body: some View {
        GeometryReader { _ in
            Color.clear
                .overlay {
                    ZStack {
                        previewLayer
                        chipLayer
                    }
                }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var previewLayer: some View {
        if let preview = document.overlapCutPreview(baseID: baseID, cutterID: cutterID) {
            documentPath([preview.cutterContour], viewport: document.viewport)
                .fill(Color.red.opacity(0.38))
            if let base = document.stroke(with: baseID), !preview.keptContours.isEmpty {
                documentPath(preview.keptContours, viewport: document.viewport)
                    .fill(keptFillColor(for: base), style: FillStyle(eoFill: preview.punchesHole))
                documentPath(preview.keptContours, viewport: document.viewport)
                    .stroke(
                        base.strokeColor.color,
                        style: StrokeStyle(
                            lineWidth: max(document.viewport.documentToView(distance: base.strokeWidth), 1),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private var chipLayer: some View {
        if let chips = document.overlapCutChipPoints(
            baseID: baseID,
            cutterID: cutterID,
            tapPoint: tapPoint,
            minimumGap: document.viewport.viewToDocument(distance: 44)
        ) {
            chip(
                at: document.viewport.documentToView(chips.kept),
                systemImage: "plus",
                glyph: SelectionHighlight.icon
            )
            chip(
                at: document.viewport.documentToView(chips.cut),
                systemImage: "minus"
            )
            chip(
                at: document.viewport.documentToView(chips.confirm),
                systemImage: "checkmark",
                prominent: true
            )
        }
    }

    private func documentPath(_ contours: [[CGPoint]], viewport: ViewportTransform) -> Path {
        var path = Path()
        for contour in contours where contour.count >= 2 {
            path.move(to: viewport.documentToView(contour[0]))
            for point in contour.dropFirst() {
                path.addLine(to: viewport.documentToView(point))
            }
            path.closeSubpath()
        }
        return path
    }

    private func keptFillColor(for stroke: VectorStroke) -> Color {
        let opacity = stroke.resolvedFillOpacity
        if let fill = stroke.fillColor {
            return Color(
                red: fill.red,
                green: fill.green,
                blue: fill.blue,
                opacity: fill.alpha * opacity
            )
        }
        return Color.gray.opacity(opacity)
    }

    /// Same chrome as the tool-panel icon buttons. The plus uses the lime icon so
    /// the kept shape is the colored mark; the check uses the olive commit fill.
    private func chip(
        at point: CGPoint,
        systemImage: String,
        glyph: Color = Color.toolPanelButtonForeground,
        prominent: Bool = false
    ) -> some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(prominent ? SelectionHighlight.icon : glyph)
            .frame(width: 26, height: 26)
            .background(prominent ? SelectionHighlight.background : Color.toolPanelButtonFill)
            .overlay {
                if !prominent {
                    Rectangle().stroke(Color.toolPanelButtonStroke, lineWidth: 1)
                }
            }
            .position(point)
    }
}
