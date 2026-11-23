//
//  DimensionOverlayView.swift
//  Koala
//

import SwiftUI

private enum DimensionFormat {
    static func display(_ value: Double, units: MeasurementUnit) -> String { units.formatted(value) }
    static func edit(_ value: Double, units: MeasurementUnit) -> String { units.formatted(value, extraDigits: 1) }
}

struct DimensionOverlayView: View {
    @Bindable var document: KoalaDocument
    /// Tap on a label that is still up outside the Dimensions tool.
    var onEditFromCanvas: (UUID) -> Void = { _ in }
    var onChanged: () -> Void = {}

    /// Document-space nudge used only to establish outward direction.
    private static let textLabelStandoff: CGFloat = 28

    @State private var labelHalfSizes: [String: CGSize] = [:]
    /// The one label showing its lock and eye; every other label is just its number.
    @State private var activeLabelKey: String?

    var body: some View {
        let strokeDimensions = visibleStrokeDimensions
        let placements = resolvedPlacements(for: strokeDimensions)
        ZStack {
            ForEach(strokeDimensions) { item in
                let placement = placements[item.id]
                DraggableDimensionLabel(
                    document: document,
                    dimension: item.dimension,
                    strokeID: item.strokeID,
                    interactive: document.activeCategory == .dimensions,
                    autoPlacement: placement?.point,
                    isCrowdedOut: placement == .hidden,
                    activeLabelKey: $activeLabelKey,
                    onEditFromCanvas: onEditFromCanvas,
                    onChanged: onChanged
                )
            }
            ForEach(visibleTextDimensions) { item in
                textDimensionLabel(item.dimension)
            }
        }
        .onPreferenceChange(DimensionLabelHalfSizesKey.self) { sizes in
            guard labelHalfSizes != sizes else { return }
            labelHalfSizes = sizes
        }
        .onChange(of: document.activeCategory) { _, category in
            if category != .dimensions { activeLabelKey = nil }
        }
    }

    /// Nudges labels the user has not dragged off each other and off neighboring dimension
    /// lines, and hides the ones that still don't fit or whose edge is too small to dimension.
    private func resolvedPlacements(
        for items: [RevealedStrokeDimension]
    ) -> [String: DimensionLabelCollision.Placement] {
        let selected = document.selectedStrokeIDs
        let collisionItems = items.map { item in
            let isActive = item.id == activeLabelKey
            let halfSize = labelHalfSizes[item.id] ?? DimensionLabelStyle.textOnlyHalfSize
            let geometry = item.dimension.viewGeometry(in: document.viewport)
            var priority = min(geometry.drawnLength, 10_000)
            if selected.contains(item.strokeID) { priority += 100_000 }
            if isActive { priority += 1_000_000 }
            return DimensionLabelCollision.Item(
                id: item.id,
                geometry: geometry,
                placement: DraggableDimensionLabel.restPosition(
                    document: document,
                    dimension: item.dimension,
                    key: item.id,
                    halfSize: halfSize
                ),
                halfSize: halfSize,
                isFixed: document.dimensionOffsets[item.id] != nil,
                canHide: !isActive,
                priority: priority
            )
        }
        return DimensionLabelCollision.resolve(collisionItems)
    }

    private struct RevealedStrokeDimension: Identifiable {
        let strokeID: UUID
        let dimension: ShapeGeometry.SemanticDimension
        var id: String {
            KoalaDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
        }
    }

    private struct RevealedTextDimension: Identifiable {
        let textID: UUID
        let dimension: TextDimension
        var id: String {
            KoalaDocument.dimensionOffsetKey(strokeID: textID, dimensionID: dimension.id)
        }
    }

    private var visibleStrokeDimensions: [RevealedStrokeDimension] {
        document.strokes.flatMap { stroke in
            ShapeGeometry.semanticDimensions(for: stroke).compactMap { dimension in
                let key = KoalaDocument.dimensionOffsetKey(strokeID: stroke.id, dimensionID: dimension.id)
                guard document.isDimensionShown(key: key) else { return nil }
                guard document.dimensionsVisible || document.isDimensionPinnedVisible(key: key) else { return nil }
                return RevealedStrokeDimension(strokeID: stroke.id, dimension: dimension)
            }
        }
    }

    private var visibleTextDimensions: [RevealedTextDimension] {
        guard document.dimensionsVisible else { return [] }
        return document.textElements.flatMap { element in
            textDimensions(for: element).compactMap { dimension in
                let key = KoalaDocument.dimensionOffsetKey(strokeID: element.id, dimensionID: dimension.id)
                guard document.isDimensionRevealed(key: key) else { return nil }
                return RevealedTextDimension(textID: element.id, dimension: dimension)
            }
        }
    }

    // MARK: - Text box dimensions (read-only width/height of the text block)

    private struct TextDimension: Identifiable {
        let id: String
        let text: String
        let start: CGPoint
        let end: CGPoint
        /// A point on the outward side of the edge, used only to pick a side.
        let outward: CGPoint
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
            start: start,
            end: end,
            outward: CGPoint(
                x: mid.x + normal.x * Self.textLabelStandoff,
                y: mid.y + normal.y * Self.textLabelStandoff
            )
        )
    }

    private func textDimensionLabel(_ dimension: TextDimension) -> some View {
        let start = document.viewport.documentToView(dimension.start)
        let end = document.viewport.documentToView(dimension.end)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let placement = DimensionLabelStyle.linearPlacement(
            midpoint: mid,
            preferred: document.viewport.documentToView(dimension.outward),
            perpendicularHalf: DimensionLabelStyle.textOnlyHalfSize.height
        )
        return PlacedLinearDimension(
            start: start,
            end: end,
            placement: placement,
            textHalfHeight: DimensionLabelStyle.textOnlyHalfSize.height
        ) {
            Text(dimension.text)
                .dimensionLabelAppearance()
        }
    }

    private func measurementLabel(_ documentValue: CGFloat) -> String {
        let pointsPerUnit = UnitConversion.pointsPerUnit(for: document.settings.units)
        let realWorldValue = documentValue / max(pointsPerUnit, 0.0001)
        let units = document.settings.units
        return "\(DimensionFormat.display(Double(realWorldValue), units: units)) \(units.shortLabel)"
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

// MARK: - Per-label drag / edit

/// Owns its own drag state so moving one label does not rebuild every other
/// dimension, and so the gesture is not fighting a parent-driven position.
private struct DraggableDimensionLabel: View {
    @Bindable var document: KoalaDocument
    let dimension: ShapeGeometry.SemanticDimension
    let strokeID: UUID
    /// False outside the Dimensions tool: the number stays up, and a tap opens it for editing.
    var interactive: Bool
    /// Collision-resolved spot for a label the user has not dragged.
    var autoPlacement: CGPoint?
    /// No room on screen; the label stays laid out (so it keeps measuring) but invisible.
    var isCrowdedOut: Bool
    @Binding var activeLabelKey: String?
    var onEditFromCanvas: (UUID) -> Void
    var onChanged: () -> Void

    @State private var isDragging = false
    @State private var dragOrigin: CGPoint = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var clusterSize: CGSize?
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editorFocused: Bool

    private var key: String {
        KoalaDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
    }

    private var halfSize: CGSize {
        clusterSize.map {
            CGSize(width: max($0.width / 2, 1), height: max($0.height / 2, 1))
        } ?? (showsControls ? DimensionLabelStyle.labeledHalfSize : DimensionLabelStyle.textOnlyHalfSize)
    }

    private var showsControls: Bool {
        interactive && activeLabelKey == key
    }

    private var isHidden: Bool {
        isCrowdedOut && !isDragging
    }

    private var restPosition: CGPoint {
        if document.dimensionOffsets[key] == nil, let autoPlacement {
            return autoPlacement
        }
        return Self.restPosition(document: document, dimension: dimension, key: key, halfSize: halfSize)
    }

    /// Where the label sits before collision avoidance: its dragged spot, or the default.
    static func restPosition(
        document: KoalaDocument,
        dimension: ShapeGeometry.SemanticDimension,
        key: String,
        halfSize: CGSize
    ) -> CGPoint {
        let anchorView = document.viewport.documentToView(dimension.anchor)
        if let offset = document.dimensionOffsets[key] {
            let docPoint = CGPoint(x: dimension.anchor.x + offset.x, y: dimension.anchor.y + offset.y)
            return document.viewport.documentToView(docPoint)
        }
        if dimension.start != nil {
            return DimensionLabelStyle.linearPlacement(
                midpoint: anchorView,
                preferred: document.viewport.documentToView(dimension.midPoint),
                perpendicularHalf: halfSize.height
            )
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
        Group {
            if let arc = arcDimension {
                PlacedArcDimension(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: arc.startAngle,
                    sweep: arc.sweep,
                    placement: labelPoint,
                    textHalfHeight: halfSize.height
                ) {
                    measuredLabel
                }
            } else if !measuresArc, let start = dimension.start, let end = dimension.end {
                PlacedLinearDimension(
                    start: document.viewport.documentToView(start),
                    end: document.viewport.documentToView(end),
                    placement: labelPoint,
                    textHalfHeight: halfSize.height
                ) {
                    measuredLabel
                }
            } else {
                radialBody
            }
        }
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .accessibilityHidden(isHidden)
        .preference(key: DimensionLabelHalfSizesKey.self, value: [key: halfSize])
        .transaction { $0.disablesAnimations = true }
    }

    private var measuredLabel: some View {
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
    }

    private var radialBody: some View {
        let anchorPoint = document.viewport.documentToView(dimension.anchor)
        let point = labelPoint
        let leaderPoint = DimensionLabelStyle.leaderEnd(
            from: anchorPoint,
            to: point,
            halfSize: halfSize
        )
        let leaderLength = hypot(leaderPoint.x - anchorPoint.x, leaderPoint.y - anchorPoint.y)

        return ZStack {
            if leaderLength > 4 {
                leader(from: anchorPoint, to: leaderPoint)
            }
            measuredLabel
                .position(point)
        }
    }

    /// At rest a label is only its number. The tapped label adds its lock and eye,
    /// value closest to the shape and eye outermost. Outside the Dimensions tool,
    /// tapping the number switches to that tool and opens the value.
    @ViewBuilder
    private var labelCluster: some View {
        if !interactive {
            Text(labelText)
                .dimensionLabelAppearance()
                .contentShape(Rectangle())
                .onTapGesture { beginEditFromCanvas() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Edit \(lockTargetName)")
        } else if !showsControls && !isEditing {
            valueLabel
        } else {
            let value = Group {
                if isEditing {
                    editorField
                } else {
                    valueLabel
                }
            }
            let lock = lockButton
            let eye = eyeButton
            if outward.x < -0.3 {
                HStack(spacing: 4) {
                    eye
                    lock
                    value
                }
            } else {
                HStack(spacing: 4) {
                    value
                    lock
                    eye
                }
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
            .dimensionLabelAppearance()
            .contentShape(Rectangle())
            .gesture(dragOrTapGesture(locked: locked))
    }

    private var lockButton: some View {
        let locked = isEdgePinned
        return Button {
            let opposite = oppositeEdgeID(for: dimension.id).map {
                KoalaDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: $0)
            }
            document.toggleDimensionLock(key: key, unlocking: opposite)
            onChanged()
        } label: {
            Image(systemName: locked ? "lock.fill" : "lock.open")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(locked ? "Unlock" : "Lock") \(lockTargetName)")
    }

    private var eyeButton: some View {
        let pinned = document.isDimensionPinnedVisible(key: key)
        return Button {
            document.toggleDimensionPinnedVisible(key: key)
            onChanged()
        } label: {
            Image(systemName: pinned ? "eye" : "eye.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            pinned
                ? "Stop showing \(lockTargetName) while drawing"
                : "Keep \(lockTargetName) visible while drawing"
        )
    }

    /// Opens this value after the canvas switches into the Dimensions tool.
    /// A locked edge still switches tools, matching tap-to-edit inside the tool.
    private func beginEditFromCanvas() {
        activeLabelKey = key
        if !isEdgePinned {
            isEditing = true
            editText = editTextValue
        }
        onEditFromCanvas(strokeID)
    }

    /// Global-space drag so translation is finger motion, not the moving label.
    /// A short press with almost no travel shows the lock and eye and opens the value.
    /// A locked edge has no value to edit, so the tap toggles its controls instead.
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
                    if locked {
                        activeLabelKey = activeLabelKey == key ? nil : key
                        return
                    }
                    activeLabelKey = key
                    isEditing = true
                    editText = editTextValue
                    return
                }
                let endPoint = CGPoint(
                    x: dragOrigin.x + value.translation.width,
                    y: dragOrigin.y + value.translation.height
                )
                let docPoint = document.viewport.viewToDocument(resolvedDragPoint(endPoint))
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
            key: KoalaDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: opposite)
        )
    }

    private var editTextValue: String {
        let display = document.settings.units.fromDocumentUnits(dimension.value)
        return DimensionFormat.edit(Double(display), units: document.settings.units)
    }

    private var measuresArc: Bool { dimension.measuresArc }

    /// Arc length, in view space, when this label measures an arc or a filleted corner.
    private var arcDimension: (center: CGPoint, radius: CGFloat, startAngle: CGFloat, sweep: CGFloat)? {
        guard case let .arc(center, radius, startAngle, sweep) = dimension.viewGeometry(in: document.viewport) else {
            return nil
        }
        return (center, radius, startAngle, sweep)
    }

    /// Drops the along-edge part of a drag so the value stays centered on the dimension line.
    private func resolvedDragPoint(_ point: CGPoint) -> CGPoint {
        if let arc = arcDimension,
           let layout = ArcDimensionLayout.layout(
            center: arc.center,
            radius: arc.radius,
            startAngle: arc.startAngle,
            sweep: arc.sweep,
            placement: point,
            textHalfHeight: halfSize.height
           ) {
            return layout.textCenter
        }
        guard let start = dimension.start, let end = dimension.end,
              let layout = LinearDimensionLayout.layout(
                start: document.viewport.documentToView(start),
                end: document.viewport.documentToView(end),
                placement: point,
                textHalfHeight: halfSize.height
              ) else { return point }
        return layout.textCenter
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
        if activeLabelKey == key { activeLabelKey = nil }
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
            key: KoalaDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: nearEdgeID)
        ) {
            return .nearEdge
        }
        if document.isDimensionLocked(
            key: KoalaDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: farEdgeID)
        ) {
            return .farEdge
        }
        return .center
    }

    private var labelText: String {
        let pointsPerUnit = UnitConversion.pointsPerUnit(for: document.settings.units)
        let realWorldValue = dimension.value / max(pointsPerUnit, 0.0001)
        let formattedValue = DimensionFormat.display(Double(realWorldValue), units: document.settings.units)
        let prefix: String
        switch dimension.kind {
        case .circleDiameter, .arcLength, .filletArc:
            prefix = "⌀ "
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
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}

private extension View {
    /// Reports the label's unrotated size so the layout can lift it clear of the dimension line.
    func measuringDimensionLabel(into size: Binding<CGSize?>) -> some View {
        fixedSize()
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: DimensionLabelSizeKey.self, value: geo.size)
                }
            }
            .onPreferenceChange(DimensionLabelSizeKey.self) { measured in
                guard measured.width > 1, measured.height > 1, size.wrappedValue != measured else { return }
                size.wrappedValue = measured
            }
    }
}

private extension ShapeGeometry.SemanticDimension {
    var measuresArc: Bool {
        switch kind {
        case .arcLength, .filletArc:
            return true
        default:
            return false
        }
    }

    /// Matches how `DraggableDimensionLabel` draws it: arc, then straight edge, then leader.
    func viewGeometry(in viewport: ViewportTransform) -> DimensionGeometry {
        if measuresArc {
            if let center = arcCenter, let sweep = arcSweep, let start {
                let radius = hypot(start.x - center.x, start.y - center.y)
                if radius > 0.5 {
                    return .arc(
                        center: viewport.documentToView(center),
                        radius: viewport.documentToView(distance: radius),
                        startAngle: atan2(start.y - center.y, start.x - center.x),
                        sweep: sweep
                    )
                }
            }
        } else if let start, let end {
            return .linear(start: viewport.documentToView(start), end: viewport.documentToView(end))
        }
        return .radial(anchor: viewport.documentToView(anchor))
    }
}

/// Each stroke label's current half-size, keyed like `dimensionOffsets`.
private struct DimensionLabelHalfSizesKey: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]

    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct DimensionClusterSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Draws a linear dimension for an edge already converted into view space.
struct PlacedLinearDimension<Label: View>: View {
    var start: CGPoint
    var end: CGPoint
    var placement: CGPoint
    var textHalfHeight: CGFloat
    @ViewBuilder var label: () -> Label

    @State private var measuredSize: CGSize?

    var body: some View {
        let layout = LinearDimensionLayout.layout(
            start: start,
            end: end,
            placement: placement,
            textHalfHeight: measuredSize.map { $0.height / 2 } ?? textHalfHeight
        )
        ZStack {
            if let layout {
                dimensionStroke(layout)
                label()
                    .measuringDimensionLabel(into: $measuredSize)
                    .rotationEffect(.radians(layout.textAngle))
                    .position(layout.textCenter)
            } else {
                label()
                    .position(placement)
            }
        }
    }

    private func dimensionStroke(_ layout: LinearDimensionLayout) -> some View {
        Path { path in
            for segment in layout.extensions + layout.shafts {
                path.move(to: segment.start)
                path.addLine(to: segment.end)
            }
            for arrow in layout.arrows {
                path.move(to: arrow.upper)
                path.addLine(to: arrow.tip)
                path.addLine(to: arrow.lower)
            }
        }
        .stroke(
            Color.accentColor.opacity(0.9),
            style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
        )
        .allowsHitTesting(false)
    }
}

/// Draws an arc-length dimension: extension lines at both ends and a concentric arc.
struct PlacedArcDimension<Label: View>: View {
    var center: CGPoint
    var radius: CGFloat
    var startAngle: CGFloat
    var sweep: CGFloat
    var placement: CGPoint
    var textHalfHeight: CGFloat
    @ViewBuilder var label: () -> Label

    @State private var measuredSize: CGSize?

    var body: some View {
        let layout = ArcDimensionLayout.layout(
            center: center,
            radius: radius,
            startAngle: startAngle,
            sweep: sweep,
            placement: placement,
            textHalfHeight: measuredSize.map { $0.height / 2 } ?? textHalfHeight
        )
        ZStack {
            if let layout {
                dimensionStroke(layout)
                label()
                    .measuringDimensionLabel(into: $measuredSize)
                    .rotationEffect(.radians(layout.textAngle))
                    .position(layout.textCenter)
            } else {
                label()
                    .position(placement)
            }
        }
    }

    private func dimensionStroke(_ layout: ArcDimensionLayout) -> some View {
        Path { path in
            for segment in layout.extensions {
                path.move(to: segment.start)
                path.addLine(to: segment.end)
            }
            for run in layout.arcRuns {
                guard let first = run.first else { continue }
                path.move(to: first)
                for point in run.dropFirst() {
                    path.addLine(to: point)
                }
            }
            for arrow in layout.arrows {
                path.move(to: arrow.upper)
                path.addLine(to: arrow.tip)
                path.addLine(to: arrow.lower)
            }
        }
        .stroke(
            Color.accentColor.opacity(0.9),
            style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
        )
        .allowsHitTesting(false)
    }
}
