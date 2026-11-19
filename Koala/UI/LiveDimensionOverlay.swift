//
//  LiveDimensionOverlay.swift
//  Koala
//

import SwiftUI

struct LiveDimensionOverlay: View {
    var document: KoalaDocument
    var start: CGPoint
    var end: CGPoint
    var category: ToolCategory
    var lineVariant: LineVariant = .line
    var circleVariant: CircleVariant
    var rectangleVariant: RectangleVariant

    var body: some View {
        let labels = liveLabels
        ForEach(labels, id: \.id) { label in
            if let start = label.start, let end = label.end {
                linearLabel(label, start: start, end: end)
            } else {
                Text(label.text)
                    .dimensionLabelAppearance()
                    .position(
                        DimensionLabelStyle.outsideLabelCenter(
                            preferred: document.viewport.documentToView(label.point),
                            from: document.viewport.documentToView(label.anchor),
                            halfSize: DimensionLabelStyle.textOnlyHalfSize
                        )
                    )
            }
        }
    }

    private func linearLabel(_ label: LiveLabel, start: CGPoint, end: CGPoint) -> some View {
        let startView = document.viewport.documentToView(start)
        let endView = document.viewport.documentToView(end)
        let mid = CGPoint(x: (startView.x + endView.x) / 2, y: (startView.y + endView.y) / 2)
        let placement = DimensionLabelStyle.linearPlacement(
            midpoint: mid,
            preferred: document.viewport.documentToView(label.point),
            perpendicularHalf: DimensionLabelStyle.textOnlyHalfSize.height
        )
        return PlacedLinearDimension(
            start: startView,
            end: endView,
            placement: placement,
            textHalfHeight: DimensionLabelStyle.textOnlyHalfSize.height
        ) {
            Text(label.text)
                .dimensionLabelAppearance()
        }
    }

    private struct LiveLabel: Identifiable {
        var id: String
        var text: String
        var point: CGPoint
        var anchor: CGPoint
        var start: CGPoint? = nil
        var end: CGPoint? = nil
    }

    private var liveLabels: [LiveLabel] {
        let units = document.settings.units
        let standoff: CGFloat = 28
        switch category {
        case .line where lineVariant == .arc:
            return radiusLabels(center: start, radial: end, units: units, standoff: standoff)
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
                point: CGPoint(x: mid.x + normal.x * standoff, y: mid.y + normal.y * standoff),
                anchor: mid,
                start: start,
                end: end
            )]
        case .circle:
            switch circleVariant {
            case .center:
                return radiusLabels(center: start, radial: end, units: units, standoff: standoff)
            case .ellipse:
                let rx = abs(end.x - start.x)
                let ry = abs(end.y - start.y)
                let top = CGPoint(x: start.x, y: start.y - ry)
                let left = CGPoint(x: start.x - rx, y: start.y)
                return [
                    LiveLabel(
                        id: "rx",
                        text: "rx " + format(rx, units: units),
                        point: CGPoint(x: top.x, y: top.y - standoff),
                        anchor: top
                    ),
                    LiveLabel(
                        id: "ry",
                        text: "ry " + format(ry, units: units),
                        point: CGPoint(x: left.x - standoff, y: left.y),
                        anchor: left
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
                let topStart = CGPoint(x: start.x - halfW, y: start.y - halfH)
                let topEnd = CGPoint(x: start.x + halfW, y: start.y - halfH)
                let rightEnd = CGPoint(x: start.x + halfW, y: start.y + halfH)
                let top = CGPoint(x: start.x, y: start.y - halfH)
                let right = CGPoint(x: start.x + halfW, y: start.y)
                return [
                    LiveLabel(
                        id: "w",
                        text: format(halfW * 2, units: units),
                        point: CGPoint(x: top.x, y: top.y - standoff),
                        anchor: top,
                        start: topStart,
                        end: topEnd
                    ),
                    LiveLabel(
                        id: "h",
                        text: format(halfH * 2, units: units),
                        point: CGPoint(x: right.x + standoff, y: right.y),
                        anchor: right,
                        start: topEnd,
                        end: rightEnd
                    )
                ]
            default:
                return []
            }
        default:
            return []
        }
    }

    private func radiusLabels(
        center: CGPoint,
        radial: CGPoint,
        units: MeasurementUnit,
        standoff: CGFloat
    ) -> [LiveLabel] {
        let radius = hypot(radial.x - center.x, radial.y - center.y)
        let top = CGPoint(x: center.x, y: center.y - radius)
        return [LiveLabel(
            id: "radius",
            text: "r " + format(radius, units: units),
            point: CGPoint(x: top.x, y: top.y - standoff),
            anchor: top
        )]
    }

    private func format(_ value: CGFloat, units: MeasurementUnit) -> String {
        let pointsPerUnit = UnitConversion.pointsPerUnit(for: units)
        let realWorldValue = value / max(pointsPerUnit, 0.0001)
        return "\(units.formatted(realWorldValue, extraDigits: 1)) \(units.shortLabel)"
    }
}
