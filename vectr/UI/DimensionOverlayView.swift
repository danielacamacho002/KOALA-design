//
//  DimensionOverlayView.swift
//  vectr
//

import SwiftUI

struct DimensionOverlayView: View {
    @Bindable var document: VectrDocument
    var onChanged: () -> Void = {}

    @State private var editingID: String?
    @State private var editText = ""

    var body: some View {
        ZStack {
            if document.dimensionsVisible,
               let strokeID = document.selectedStrokeID,
               let stroke = document.stroke(with: strokeID) {
                ForEach(ShapeGeometry.semanticDimensions(for: stroke)) { dimension in
                    dimensionPill(dimension, strokeID: strokeID)
                }
            }
        }
    }

    @ViewBuilder
    private func dimensionPill(_ dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) -> some View {
        let viewPoint = document.viewport.documentToView(dimension.midPoint)
        if editingID == dimension.id {
            TextField("", text: $editText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 88)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemBackground), in: Capsule())
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
                .position(viewPoint)
                .onSubmit { commitEdit(dimension: dimension, strokeID: strokeID) }
                .onAppear {
                    let display = document.settings.units.fromDocumentUnits(dimension.value)
                    editText = String(format: "%.3f", display)
                }
        } else {
            Button {
                editingID = dimension.id
                let display = document.settings.units.fromDocumentUnits(dimension.value)
                editText = String(format: "%.3f", display)
            } label: {
                Text(labelText(for: dimension))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemBackground), in: Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .position(viewPoint)
        }
    }

    private func commitEdit(dimension: ShapeGeometry.SemanticDimension, strokeID: UUID) {
        editingID = nil
        guard let value = Double(editText.trimmingCharacters(in: .whitespaces)),
              let stroke = document.stroke(with: strokeID) else { return }
        let docValue = document.settings.units.toDocumentUnits(CGFloat(value))
        guard let updated = ShapeGeometry.applyDimension(dimension, newValue: docValue, to: stroke) else { return }
        document.updateStroke(updated)
        onChanged()
    }

    private func labelText(for dimension: ShapeGeometry.SemanticDimension) -> String {
        let pointsPerUnit = UnitConversion.pointsPerUnit(for: document.settings.units)
        let realWorldValue = dimension.value / max(pointsPerUnit, 0.0001)
        let formattedValue = String(format: "%.3f", realWorldValue)
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
