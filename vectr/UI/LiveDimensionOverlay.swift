//
//  LiveDimensionOverlay.swift
//  vectr
//

import SwiftUI

struct LiveDimensionOverlay: View {
    var document: VectrDocument
    var start: CGPoint
    var end: CGPoint
    var category: ToolCategory
    var circleVariant: CircleVariant
    var rectangleVariant: RectangleVariant

    var body: some View {
        let labels = liveLabels
        ForEach(labels, id: \.id) { label in
            Text(label.text)
                .dimensionLabelAppearance()
                .position(document.viewport.documentToView(label.point))
        }
    }

    private struct LiveLabel: Identifiable {
        var id: String
        var text: String
        var point: CGPoint
    }

    private var liveLabels: [LiveLabel] {
        let units = document.settings.units
        let standoff: CGFloat = 28
        switch category {
        case .line:
            let length = hypot(end.x - start.x, end.y - start.y)
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let edgeLength = hypot(dx, dy)
            let normal = edgeLength > 0.001
                ? CGPoint(x: -dy / edgeLength, y: dx / edgeLength)
                : CGPoint(x: 0, y: -1)
            return [LiveLabel(
                id: "length",
                text: format(length, units: units),
                point: CGPoint(x: mid.x + normal.x * standoff, y: mid.y + normal.y * standoff)
            )]
        case .circle:
            switch circleVariant {
            case .center:
                let radius = hypot(end.x - start.x, end.y - start.y)
                return [LiveLabel(
                    id: "radius",
                    text: "r " + format(radius, units: units),
                    point: CGPoint(x: start.x, y: start.y - radius - standoff)
                )]
            case .ellipse:
                let rx = abs(end.x - start.x)
                let ry = abs(end.y - start.y)
                return [
                    LiveLabel(
                        id: "rx",
                        text: "rx " + format(rx, units: units),
                        point: CGPoint(x: start.x, y: start.y - ry - standoff)
                    ),
                    LiveLabel(
                        id: "ry",
                        text: "ry " + format(ry, units: units),
                        point: CGPoint(x: start.x - rx - standoff, y: start.y)
                    )
                ]
            default:
                return []
            }
        case .rectangle:
            switch rectangleVariant {
            case .center:
                let halfW = abs(end.x - start.x)
                let halfH = abs(end.y - start.y)
                return [
                    LiveLabel(
                        id: "w",
                        text: format(halfW * 2, units: units),
                        point: CGPoint(x: start.x, y: start.y - halfH - standoff)
                    ),
                    LiveLabel(
                        id: "h",
                        text: format(halfH * 2, units: units),
                        point: CGPoint(x: start.x + halfW + standoff, y: start.y)
                    )
                ]
            default:
                return []
            }
        default:
            return []
        }
    }

    private func format(_ value: CGFloat, units: MeasurementUnit) -> String {
        let pointsPerUnit = UnitConversion.pointsPerUnit(for: units)
        let realWorldValue = value / max(pointsPerUnit, 0.0001)
        return String(format: "%.3f %@", realWorldValue, units.shortLabel)
    }
}
