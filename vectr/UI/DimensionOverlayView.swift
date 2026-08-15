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
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack {
            if document.dimensionsVisible,
               let strokeID = document.selectedStrokeID,
               let stroke = document.stroke(with: strokeID) {
                ForEach(ShapeGeometry.semanticDimensions(for: stroke)) { dimension in
                    dimensionPill(dimension, strokeID: strokeID)
                }
            } else if document.dimensionsVisible,
                      let textID = document.selectedTextID,
                      let element = document.textElement(with: textID) {
                ForEach(textDimensions(for: element)) { dimension in
                    textDimensionPill(dimension)
                }
            }
        }
    }

    // MARK: - Text box dimensions (read-only width/height of the text block)

    private struct TextDimension: Identifiable {
        let id: String
        let text: String
        let midPoint: CGPoint
    }

    private func textDimensions(for element: TextElement) -> [TextDimension] {
        let size = element.textSize()
        let corners = element.corners()
        guard corners.count == 4 else { return [] }
        return [
            TextDimension(
                id: "text-width",
                text: measurementLabel(size.width),
                midPoint: midpoint(corners[3], corners[2])
            ),
            TextDimension(
                id: "text-height",
                text: measurementLabel(size.height),
                midPoint: midpoint(corners[0], corners[3])
            )
        ]
    }

    private func textDimensionPill(_ dimension: TextDimension) -> some View {
        Text(dimension.text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            .position(document.viewport.documentToView(dimension.midPoint))
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
        if let offset = document.dimensionOffsets[key] {
            let docPoint = CGPoint(x: dimension.anchor.x + offset.x, y: dimension.anchor.y + offset.y)
            return document.viewport.documentToView(docPoint)
        }
        return document.viewport.documentToView(dimension.midPoint)
    }

    private func livePosition(for dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> CGPoint {
        let base = basePosition(for: dimension, strokeID: strokeID)
        guard draggingID == dimension.id else { return base }
        return CGPoint(x: base.x + dragTranslation.width, y: base.y + dragTranslation.height)
    }

    @ViewBuilder
    private func dimensionPill(_ dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        let anchorPoint = document.viewport.documentToView(dimension.anchor)
        let labelPoint = livePosition(for: dimension, strokeID: strokeID)
        let leaderLength = hypot(labelPoint.x - anchorPoint.x, labelPoint.y - anchorPoint.y)

        if leaderLength > 12 {
            leader(from: anchorPoint, to: labelPoint)
        }

        HStack(spacing: 4) {
            if editingID == dimension.id {
                editorField(dimension: dimension, strokeID: strokeID)
            } else {
                valueCapsule(dimension: dimension, strokeID: strokeID)
            }

            if supportsLock(dimension) {
                lockButton(dimension: dimension, strokeID: strokeID)
            }
        }
        .position(labelPoint)
    }

    private func editorField(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        TextField("", text: $editText)
            .font(.caption.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 88)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
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

    private func valueCapsule(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        let locked = isLocked(dimension, strokeID: strokeID)
        return Text(labelText(for: dimension))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(locked ? Color.secondary : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(
                Capsule().stroke(
                    locked ? Color.secondary.opacity(0.35) : Color.accentColor.opacity(0.35),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
            .onTapGesture {
                guard !locked else { return }
                editingID = dimension.id
                editText = editTextValue(for: dimension)
            }
            .gesture(dragGesture(dimension: dimension, strokeID: strokeID))
    }

    private func lockButton(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        let locked = isLocked(dimension, strokeID: strokeID)
        return Button {
            let key = VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
            document.toggleDimensionLock(key: key)
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
        .accessibilityLabel("\(locked ? "Unpin" : "Pin") \(axisName(for: dimension)) edge")
    }

    private func axisName(for dimension: ShapeGeometry.SemanticDimension) -> String {
        switch dimension.kind {
        case .rectangleWidth: return "length"
        case .rectangleHeight: return "height"
        default: return "dimension"
        }
    }

    /// Pinning only has meaning where two dimensions share a shape and one can be held
    /// while the other is resized.
    private func supportsLock(_ dimension: ShapeGeometry.SemanticDimension) -> Bool {
        switch dimension.kind {
        case .rectangleWidth, .rectangleHeight: return true
        default: return false
        }
    }

    private func isLocked(_ dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> Bool {
        document.isDimensionLocked(
            key: VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: dimension.id)
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
            .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
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
        guard let updated = ShapeGeometry.applyDimension(
            dimension,
            newValue: docValue,
            to: stroke,
            anchor: anchor(for: dimension, strokeID: strokeID)
        ) else { return }
        document.updateStroke(updated)
        onChanged()
    }

    /// A pinned dimension holds the edge its own pill sits on, which is the far edge of
    /// the perpendicular axis. With nothing pinned the shape grows away from its origin
    /// corner so it never recenters.
    private func anchor(
        for dimension: ShapeGeometry.SemanticDimension,
        strokeID: UUID
    ) -> ShapeGeometry.DimensionAnchor {
        let counterpartID: String
        switch dimension.kind {
        case .rectangleWidth: counterpartID = "height"
        case .rectangleHeight: counterpartID = "width"
        default: return .nearEdge
        }
        let key = VectrDocument.dimensionOffsetKey(strokeID: strokeID, dimensionID: counterpartID)
        return document.isDimensionLocked(key: key) ? .farEdge : .nearEdge
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
        case .rectangleWidth:
            prefix = "L "
        case .rectangleHeight:
            prefix = "H "
        default:
            prefix = ""
        }
        return "\(prefix)\(formattedValue) \(document.settings.units.shortLabel)"
    }
}
