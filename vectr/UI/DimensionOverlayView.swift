//
//  DimensionOverlayView.swift
//  vectr
//

import SwiftUI

private enum DimensionFormat {
    static func display(_ value: Double) -> String { String(format: "%.2f", value) }
    static func edit(_ value: Double) -> String { String(format: "%.3f", value) }
}

struct DimensionOverlayView: View {
    @Bindable var document: VectrDocument
    var onChanged: () -> Void = {}

    @State private var editingID: String?
    @State private var editText = ""
    @State private var draggingID: String?
    @State private var dragTranslation: CGSize = .zero
    /// Measured sizes of each dimension label cluster (value + lock), used so wide
    /// side labels clear the stroke instead of sitting on the border.
    @State private var labelClusterSizes: [String: CGSize] = [:]
    @FocusState private var editorFocused: Bool

    /// Document-space nudge used only to establish outward direction.
    private static let textLabelStandoff: CGFloat = 28

    var body: some View {
        ZStack {
            if document.dimensionsVisible,
               let strokeID = document.selectedStrokeID,
               let stroke = document.stroke(with: strokeID) {
                ForEach(ShapeGeometry.semanticDimensions(for: stroke)) { dimension in
                    dimensionLabel(dimension, strokeID: strokeID)
                }
            } else if document.dimensionsVisible,
                      let textID = document.selectedTextID,
                      let element = document.textElement(with: textID) {
                ForEach(textDimensions(for: element)) { dimension in
                    textDimensionLabel(dimension)
                }
            }
        }
    }

    // MARK: - Text box dimensions (read-only width/height of the text block)

    private struct TextDimension: Identifiable {
        let id: String
        let text: String
        let midPoint: CGPoint
        let anchor: CGPoint
    }

    private func textDimensions(for element: TextElement) -> [TextDimension] {
        let size = element.textSize()
        let corners = element.corners()
        guard corners.count == 4 else { return [] }
        let centroid = CGPoint(
            x: (corners[0].x + corners[1].x + corners[2].x + corners[3].x) / 4,
            y: (corners[0].y + corners[1].y + corners[2].y + corners[3].y) / 4
        )
        return [
            textDimension(
                id: "text-width",
                text: measurementLabel(size.width),
                start: corners[3],
                end: corners[2],
                awayFrom: centroid
            ),
            textDimension(
                id: "text-height",
                text: measurementLabel(size.height),
                start: corners[0],
                end: corners[3],
                awayFrom: centroid
            )
        ]
    }

    private func textDimension(
        id: String,
        text: String,
        start: CGPoint,
        end: CGPoint,
        awayFrom reference: CGPoint
    ) -> TextDimension {
        let mid = midpoint(start, end)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        let normal: CGPoint
        if length > 0.001 {
            let ccw = CGPoint(x: -dy / length, y: dx / length)
            let away = CGPoint(x: mid.x - reference.x, y: mid.y - reference.y)
            normal = ccw.x * away.x + ccw.y * away.y >= 0
                ? ccw
                : CGPoint(x: -ccw.x, y: -ccw.y)
        } else {
            normal = CGPoint(x: 0, y: -1)
        }
        return TextDimension(
            id: id,
            text: text,
            midPoint: CGPoint(
                x: mid.x + normal.x * Self.textLabelStandoff,
                y: mid.y + normal.y * Self.textLabelStandoff
            ),
            anchor: mid
        )
    }

    private func textDimensionLabel(_ dimension: TextDimension) -> some View {
        Text(dimension.text)
            .dimensionLabelAppearance()
            .position(
                DimensionLabelStyle.outsideLabelCenter(
                    preferred: document.viewport.documentToView(dimension.midPoint),
                    from: document.viewport.documentToView(dimension.anchor),
                    halfSize: DimensionLabelStyle.textOnlyHalfSize
                )
            )
    }

    private func measurementLabel(_ documentValue: CGFloat) -> String {
        let pointsPerUnit = UnitConversion.pointsPerUnit(for: document.settings.units)
        let realWorldValue = documentValue / max(pointsPerUnit, 0.0001)
        return "\(DimensionFormat.display(Double(realWorldValue))) \(document.settings.units.shortLabel)"
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    // MARK: - Shape dimensions (draggable, with leader lines)

    /// View-space position where the label should sit, honoring any stored drag offset.
    private func basePosition(for dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> CGPoint {
        let key = VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
        let anchorView = document.viewport.documentToView(dimension.anchor)
        if let offset = document.dimensionOffsets[key] {
            let docPoint = CGPoint(x: dimension.anchor.x + offset.x, y: dimension.anchor.y + offset.y)
            return document.viewport.documentToView(docPoint)
        }
        let preferred = document.viewport.documentToView(dimension.midPoint)
        let measured = labelClusterSizes[dimension.id]
        let halfSize = measured.map {
            CGSize(width: max($0.width / 2, 1), height: max($0.height / 2, 1))
        } ?? DimensionLabelStyle.labeledHalfSize
        return DimensionLabelStyle.outsideLabelCenter(
            preferred: preferred,
            from: anchorView,
            halfSize: halfSize
        )
    }

    private func livePosition(for dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> CGPoint {
        let base = basePosition(for: dimension, strokeID: strokeID)
        guard draggingID == dimension.id else { return base }
        return CGPoint(x: base.x + dragTranslation.width, y: base.y + dragTranslation.height)
    }

    private func viewOutward(for dimension: ShapeGeometry.SemanticDimension) -> CGPoint {
        DimensionLabelStyle.outwardUnit(
            preferred: document.viewport.documentToView(dimension.midPoint),
            from: document.viewport.documentToView(dimension.anchor)
        )
    }

    @ViewBuilder
    private func dimensionLabel(_ dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        let anchorPoint = document.viewport.documentToView(dimension.anchor)
        let labelPoint = livePosition(for: dimension, strokeID: strokeID)
        let outward = viewOutward(for: dimension)
        let leaderLength = hypot(labelPoint.x - anchorPoint.x, labelPoint.y - anchorPoint.y)

        if leaderLength > 12 {
            leader(from: anchorPoint, to: labelPoint)
        }

        labelCluster(dimension: dimension, strokeID: strokeID, outward: outward)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: DimensionLabelSizeKey.self,
                        value: [dimension.id: geo.size]
                    )
                }
            )
            .onPreferenceChange(DimensionLabelSizeKey.self) { sizes in
                for (id, size) in sizes where labelClusterSizes[id] != size {
                    labelClusterSizes[id] = size
                }
            }
            .position(labelPoint)
    }

    /// Keep the lock on the outside of the shape so the value sits closer to the edge
    /// and the cluster's outward half isn't wasted on empty space.
    @ViewBuilder
    private func labelCluster(
        dimension: ShapeGeometry.SemanticDimension,
        strokeID: UUID,
        outward: CGPoint
    ) -> some View {
        let value = Group {
            if editingID == dimension.id {
                editorField(dimension: dimension, strokeID: strokeID)
            } else {
                valueLabel(dimension: dimension, strokeID: strokeID)
            }
        }
        let lock = lockButton(dimension: dimension, strokeID: strokeID)
        // Left-side labels: lock then value. Everywhere else: value then lock.
        if outward.x < -0.3 {
            HStack(spacing: 4) {
                lock
                value
            }
        } else {
            HStack(spacing: 4) {
                value
                lock
            }
        }
    }

    private func editorField(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        TextField("", text: $editText)
            .font(DimensionLabelStyle.font)
            .foregroundStyle(Color.accentColor)
            .multilineTextAlignment(.center)
            .frame(width: 88)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 1.5)
            }
            .focused($editorFocused)
            .submitLabel(.done)
            .onSubmit { commitEdit(dimension: dimension, strokeID: strokeID) }
            .onChange(of: editorFocused) { _, focused in
                // Tapping elsewhere should commit rather than strand the editor.
                if !focused { commitEdit(dimension: dimension, strokeID: strokeID) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                (note.object as? UITextField)?.selectAll(nil)
            }
            .onAppear {
                editText = editTextValue(for: dimension)
                editorFocused = true
            }
    }

    private func valueLabel(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        let locked = isEdgePinned(dimension, strokeID: strokeID)
        return Text(labelText(for: dimension))
            .dimensionLabelAppearance(locked: locked)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !locked else { return }
                editingID = dimension.id
                editText = editTextValue(for: dimension)
            }
            .gesture(dragGesture(dimension: dimension, strokeID: strokeID))
    }

    private func lockButton(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        let locked = isEdgePinned(dimension, strokeID: strokeID)
        return Button {
            let key = VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
            let opposite = oppositeEdgeID(for: dimension.id).map {
                VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: $0)
            }
            document.toggleDimensionLock(key: key, unlocking: opposite)
            onChanged()
        } label: {
            Image(systemName: locked ? "lock.fill" : "lock.open")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(locked ? Color.accentColor : Color.secondary)
                .frame(width: 26, height: 26)
                .background(Color(.systemBackground), in: Circle())
                .overlay(
                    Circle().stroke(
                        locked ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: locked ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(locked ? "Unlock" : "Lock") \(lockTargetName(for: dimension))")
    }

    /// Rectangle locks pin a named edge; everywhere else the lock simply freezes the
    /// value against edits.
    private func lockTargetName(for dimension: ShapeGeometry.SemanticDimension) -> String {
        if ShapeGeometry.RectangleEdge(rawValue: dimension.id) != nil {
            return "\(edgeName(for: dimension.id)) edge"
        }
        return "dimension"
    }

    /// The label on the parallel edge showing the same value. Pinning one edge releases
    /// the other so an axis can never be pinned on both sides.
    private func oppositeEdgeID(for dimensionID: String) -> String? {
        switch dimensionID {
        case "width-top": return "width-bottom"
        case "width-bottom": return "width-top"
        case "height-left": return "height-right"
        case "height-right": return "height-left"
        default: return nil
        }
    }

    private func edgeName(for dimensionID: String) -> String {
        dimensionID.split(separator: "-").last.map(String.init) ?? "shape"
    }

    /// Whether this specific edge is pinned. A pinned edge is frozen in place and its
    /// label refuses edits; the opposite label stays editable so the two edges can hold
    /// different values.
    private func isEdgePinned(_ dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> Bool {
        document.isDimensionLocked(
            key: VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
        )
    }

    /// Whether the parallel edge across the shape is pinned, which switches edits of
    /// this label from whole-axis resizing to reshaping just this edge.
    private func isOppositeEdgePinned(_ dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> Bool {
        guard let opposite = oppositeEdgeID(for: dimension.id) else { return false }
        return document.isDimensionLocked(
            key: VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: opposite)
        )
    }

    private func editTextValue(for dimension: ShapeGeometry.SemanticDimension) -> String {
        let display = document.settings.units.fromDocumentUnits(dimension.value)
        return DimensionFormat.edit(Double(display))
    }

    private func leader(from start: CGPoint, to end: CGPoint) -> some View {
        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)

            Circle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 4, height: 4)
                .position(start)
        }
        .allowsHitTesting(false)
    }

    private func dragGesture(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                draggingID = dimension.id
                dragTranslation = value.translation
            }
            .onEnded { value in
                let base = basePosition(for: dimension, strokeID: strokeID)
                let endPoint = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                let docPoint = document.viewport.viewToDocument(endPoint)
                let key = VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
                let offset = CGPoint(x: docPoint.x - dimension.anchor.x, y: docPoint.y - dimension.anchor.y)
                document.setDimensionOffset(key: key, offset: offset)
                draggingID = nil
                dragTranslation = .zero
                onChanged()
            }
    }

    private func commitEdit(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) {
        // Submitting drops focus, so both paths land here; only the first should apply.
        guard editingID == dimension.id else { return }
        editingID = nil
        guard let value = Double(editText.trimmingCharacters(in: .whitespaces)),
              value.isFinite,
              value > 0,
              let stroke = document.stroke(with: strokeID) else { return }
        let docValue = document.settings.units.toDocumentUnits(CGFloat(value))
        let updated: VectorStroke?
        if let edge = ShapeGeometry.RectangleEdge(rawValue: dimension.id) {
            if isOppositeEdgePinned(dimension, strokeID: strokeID) {
                // The parallel edge is pinned, so reshape just this edge; opposite
                // edges may then differ and the shape becomes a free quad.
                updated = ShapeGeometry.applyEdgeLength(edge, newValue: docValue, to: stroke)
            } else {
                // Paired edit: adjacent sides stay rigid and slide apart, so the
                // unlocked partner edge resizes along with this one.
                updated = ShapeGeometry.applyQuadEdge(
                    edge,
                    newValue: docValue,
                    to: stroke,
                    anchor: anchor(for: dimension, strokeID: strokeID)
                )
            }
        } else {
            updated = ShapeGeometry.applyDimension(dimension, newValue: docValue, to: stroke)
        }
        guard let updated else { return }
        document.updateStroke(updated)
        onChanged()
    }

    /// A pinned edge stays put when the perpendicular axis is edited; with nothing
    /// pinned the shape resizes about its center. Near/far follow the local frame:
    /// the near width edge is the left one, the near height edge is the top one.
    private func anchor(
        for dimension: ShapeGeometry.SemanticDimension,
        strokeID: UUID
    ) -> ShapeGeometry.DimensionAnchor {
        let nearEdgeID: String
        let farEdgeID: String
        switch dimension.kind {
        case .rectangleWidth:
            nearEdgeID = "height-left"
            farEdgeID = "height-right"
        case .rectangleHeight:
            nearEdgeID = "width-top"
            farEdgeID = "width-bottom"
        default:
            return .center
        }
        if document.isDimensionLocked(key: VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: nearEdgeID)) {
            return .nearEdge
        }
        if document.isDimensionLocked(key: VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: farEdgeID)) {
            return .farEdge
        }
        return .center
    }

    private func labelText(for dimension: ShapeGeometry.SemanticDimension) -> String {
        let pointsPerUnit = UnitConversion.pointsPerUnit(for: document.settings.units)
        let realWorldValue = dimension.value / max(pointsPerUnit, 0.0001)
        let formattedValue = DimensionFormat.display(Double(realWorldValue))
        let prefix: String
        switch dimension.kind {
        case .circleDiameter:
            prefix = "d "
        case .ellipseRX:
            prefix = "rx "
        case .ellipseRY:
            prefix = "ry "
        default:
            prefix = ""
        }
        return "\(prefix)\(formattedValue) \(document.settings.units.shortLabel)"
    }
}

private struct DimensionLabelSizeKey: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]

    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
