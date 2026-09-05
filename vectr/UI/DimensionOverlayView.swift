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

    /// Document-space nudge used only to establish outward direction.
    private static let textLabelStandoff: CGFloat = 28

    var body: some View {
        ZStack {
            if document.dimensionsVisible {
                ForEach(visibleStrokeDimensions) { item in
                    DraggableDimensionLabel(
                        document: document,
                        dimension: item.dimension,
                        strokeID: item.strokeID,
                        onChanged: onChanged
                    )
                }
                ForEach(visibleTextDimensions) { item in
                    textDimensionLabel(item.dimension)
                }
            }
        }
    }

    private struct RevealedStrokeDimension: Identifiable {
        let strokeID: UUID
        let dimension: ShapeGeometry.SemanticDimension
        var id: String {
            VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
        }
    }

    private struct RevealedTextDimension: Identifiable {
        let textID: UUID
        let dimension: TextDimension
        var id: String {
            VectrDocument.dimensionOffsetKey(strokeID: textID, dimensionID: dimension.id)
        }
    }

    private var visibleStrokeDimensions: [RevealedStrokeDimension] {
        document.strokes.flatMap { stroke in
            ShapeGeometry.semanticDimensions(for: stroke).compactMap { dimension in
                let key = VectrDocument.dimensionOffsetKey(strokeID: stroke.id, dimensionID: dimension.id)
                guard document.isDimensionRevealed(key: key) else { return nil }
                return RevealedStrokeDimension(strokeID: stroke.id, dimension: dimension)
            }
        }
    }

    private var visibleTextDimensions: [RevealedTextDimension] {
        document.textElements.flatMap { element in
            textDimensions(for: element).compactMap { dimension in
                let key = VectrDocument.dimensionOffsetKey(strokeID: element.id, dimensionID: dimension.id)
                guard document.isDimensionRevealed(key: key) else { return nil }
                return RevealedTextDimension(textID: element.id, dimension: dimension)
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
}

// MARK: - Per-label drag / edit

/// Owns its own drag state so moving one label does not rebuild every other
/// dimension, and so the gesture is not fighting a parent-driven position.
private struct DraggableDimensionLabel: View {
    @Bindable var document: VectrDocument
    let dimension: ShapeGeometry.SemanticDimension
    let strokeID: UUID
    var onChanged: () -> Void

    @State private var isDragging = false
    @State private var dragOrigin: CGPoint = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var clusterSize: CGSize?
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editorFocused: Bool

    private var key: String {
        VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
    }

    private var halfSize: CGSize {
        clusterSize.map {
            CGSize(width: max($0.width / 2, 1), height: max($0.height / 2, 1))
        } ?? DimensionLabelStyle.labeledHalfSize
    }

    private var restPosition: CGPoint {
        let anchorView = document.viewport.documentToView(dimension.anchor)
        if let offset = document.dimensionOffsets[key] {
            let docPoint = CGPoint(x: dimension.anchor.x + offset.x, y: dimension.anchor.y + offset.y)
            return document.viewport.documentToView(docPoint)
        }
        return DimensionLabelStyle.outsideLabelCenter(
            preferred: document.viewport.documentToView(dimension.midPoint),
            from: anchorView,
            halfSize: halfSize
        )
    }

    private var labelPoint: CGPoint {
        guard isDragging else { return restPosition }
        return CGPoint(
            x: dragOrigin.x + dragTranslation.width,
            y: dragOrigin.y + dragTranslation.height
        )
    }

    private var outward: CGPoint {
        DimensionLabelStyle.outwardUnit(
            preferred: document.viewport.documentToView(dimension.midPoint),
            from: document.viewport.documentToView(dimension.anchor)
        )
    }

    var body: some View {
        let anchorPoint = document.viewport.documentToView(dimension.anchor)
        let point = labelPoint
        let leaderPoint = DimensionLabelStyle.leaderEnd(
            from: anchorPoint,
            to: point,
            halfSize: halfSize
        )
        let leaderLength = hypot(leaderPoint.x - anchorPoint.x, leaderPoint.y - anchorPoint.y)

        ZStack {
            if leaderLength > 4 {
                leader(from: anchorPoint, to: leaderPoint)
            }

            labelCluster
                .fixedSize()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: DimensionClusterSizeKey.self, value: geo.size)
                    }
                )
                .onPreferenceChange(DimensionClusterSizeKey.self) { size in
                    guard !isDragging, size.width > 1, size.height > 1, clusterSize != size else { return }
                    clusterSize = size
                }
                .position(point)
        }
        .transaction { $0.disablesAnimations = true }
    }

    /// Keep the lock on the outside of the shape so the value sits closer to the edge
    /// and the cluster's outward half isn't wasted on empty space.
    @ViewBuilder
    private var labelCluster: some View {
        let value = Group {
            if isEditing {
                editorField
            } else {
                valueLabel
            }
        }
        let lock = lockButton
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

    private var editorField: some View {
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
            .onSubmit { commitEdit() }
            .onChange(of: editorFocused) { _, focused in
                if !focused { commitEdit() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                (note.object as? UITextField)?.selectAll(nil)
            }
            .onAppear {
                editText = editTextValue
                editorFocused = true
            }
    }

    private var valueLabel: some View {
        let locked = isEdgePinned
        return Text(labelText)
            .dimensionLabelAppearance(locked: locked)
            .contentShape(Rectangle())
            .gesture(dragOrTapGesture(locked: locked))
    }

    private var lockButton: some View {
        let locked = isEdgePinned
        return Button {
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
        .accessibilityLabel("\(locked ? "Unlock" : "Lock") \(lockTargetName)")
    }

    /// Global-space drag so translation is finger motion, not the moving label.
    /// A short press with almost no travel becomes tap-to-edit.
    private func dragOrTapGesture(locked: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragOrigin = restPosition
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                let travel = hypot(value.translation.width, value.translation.height)
                if travel < 4 {
                    isDragging = false
                    dragTranslation = .zero
                    guard !locked else { return }
                    isEditing = true
                    editText = editTextValue
                    return
                }
                let endPoint = CGPoint(
                    x: dragOrigin.x + value.translation.width,
                    y: dragOrigin.y + value.translation.height
                )
                let docPoint = document.viewport.viewToDocument(endPoint)
                let offset = CGPoint(
                    x: docPoint.x - dimension.anchor.x,
                    y: docPoint.y - dimension.anchor.y
                )
                document.setDimensionOffset(key: key, offset: offset)
                isDragging = false
                dragTranslation = .zero
                onChanged()
            }
    }

    private var lockTargetName: String {
        if ShapeGeometry.RectangleEdge(rawValue: dimension.id) != nil {
            return "\(edgeName(for: dimension.id)) edge"
        }
        return "dimension"
    }

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

    private var isEdgePinned: Bool {
        document.isDimensionLocked(key: key)
    }

    private var isOppositeEdgePinned: Bool {
        guard let opposite = oppositeEdgeID(for: dimension.id) else { return false }
        return document.isDimensionLocked(
            key: VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: opposite)
        )
    }

    private var editTextValue: String {
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

    private func commitEdit() {
        guard isEditing else { return }
        isEditing = false
        guard let value = Double(editText.trimmingCharacters(in: .whitespaces)),
              value.isFinite,
              value > 0,
              let stroke = document.stroke(with: strokeID) else { return }
        let docValue = document.settings.units.toDocumentUnits(CGFloat(value))
        let updated: VectorStroke?
        if let edge = ShapeGeometry.RectangleEdge(rawValue: dimension.id) {
            if isOppositeEdgePinned {
                updated = ShapeGeometry.applyEdgeLength(edge, newValue: docValue, to: stroke)
            } else {
                updated = ShapeGeometry.applyQuadEdge(
                    edge,
                    newValue: docValue,
                    to: stroke,
                    anchor: resizeAnchor
                )
            }
        } else {
            updated = ShapeGeometry.applyDimension(dimension, newValue: docValue, to: stroke)
        }
        guard let updated else { return }
        document.updateStroke(updated)
        onChanged()
    }

    private var resizeAnchor: ShapeGeometry.DimensionAnchor {
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
        if document.isDimensionLocked(
            key: VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: nearEdgeID)
        ) {
            return .nearEdge
        }
        if document.isDimensionLocked(
            key: VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: farEdgeID)
        ) {
            return .farEdge
        }
        return .center
    }

    private var labelText: String {
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

private struct DimensionClusterSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
