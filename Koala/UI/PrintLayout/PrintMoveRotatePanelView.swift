//
//  PrintMoveRotatePanelView.swift
//  Koala
//

import SwiftUI

/// Command panel shown when an element is selected in Print Layout. Includes
/// optional axis-locked move, absolute-degree rotate, an opt-in rotate handle,
/// and flip.
struct PrintMoveRotatePanelView: View {
    @Bindable var document: KoalaDocument
    @Binding var rotateModeActive: Bool
    @Binding var axisLockEnabled: Bool
    var onChanged: () -> Void
    var onClose: () -> Void

    @State private var degreesText = ""

    private var selectedID: UUID? {
        document.printSelectedStrokeID ?? document.printSelectedTextID
    }

    private var currentDegrees: Double {
        guard let id = selectedID else { return 0 }
        return ShapeGeometry.normalizedRotationDegrees(document.printTransform(for: id).rotation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Move")
                Spacer()
                ToolPanelCancelButton { onClose() }
            }

            ToolPanelLabelButton(
                title: axisLockEnabled ? "Axis locked" : "Lock to XY axis",
                prominent: axisLockEnabled,
                fullWidth: true
            ) {
                axisLockEnabled.toggle()
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ToolPanelSectionLabel("Rotate")

                ToolPanelNumericStepper(
                    text: $degreesText,
                    placeholder: "0",
                    unitLabel: "°",
                    keyboardType: .numbersAndPunctuation,
                    onMinus: { stepRotation(by: -1) },
                    onPlus: { stepRotation(by: 1) },
                    onSubmit: apply
                )

                ToolPanelLabelButton(
                    title: "Rotate",
                    prominent: rotateModeActive,
                    fullWidth: true
                ) {
                    rotateModeActive.toggle()
                }
            }

            Divider()

            ToolPanelSectionLabel("Flip")
            HStack(spacing: 0) {
                ToolPanelLabelButton(title: "Flip H", fullWidth: true) {
                    toggleFlip(horizontal: true)
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 16)
                ToolPanelLabelButton(title: "Flip V", fullWidth: true) {
                    toggleFlip(horizontal: false)
                }
            }
            .background(Color.toolPanelButtonFill)
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
        .onAppear { syncDegreesField() }
        .onChange(of: document.printSelectedStrokeID) { _, _ in syncDegreesField() }
        .onChange(of: document.printSelectedTextID) { _, _ in syncDegreesField() }
        .onChange(of: document.printLayoutRevision) { _, _ in syncDegreesFieldFromCurrent() }
    }

    private func syncDegreesField() {
        degreesText = String(format: "%.1f", currentDegrees)
    }

    /// Keeps the field in sync with live changes, but never clobbers a value the
    /// user is actively typing (only refreshes when empty or non-numeric).
    private func syncDegreesFieldFromCurrent() {
        guard degreesText.isEmpty
            || Double(degreesText.trimmingCharacters(in: .whitespaces)) == nil else { return }
        syncDegreesField()
    }

    private func apply() {
        guard let value = Double(degreesText.trimmingCharacters(in: .whitespaces)) else { return }
        setRotation(toDegrees: value)
    }

    private func stepRotation(by delta: Double) {
        setRotation(toDegrees: currentDegrees + delta)
    }

    private func setRotation(toDegrees value: Double) {
        let ids = document.printSelectedIDs
        guard !ids.isEmpty else { return }
        document.beginInteractiveEdit()
        let target = CGFloat(value * .pi / 180)
        if ids.count == 1, let id = ids.first {
            var transform = document.printTransform(for: id)
            transform.rotation = target
            document.setPrintTransform(transform, for: id, recordUndo: false)
        } else if let bbox = document.printSelectionBoundingBox(),
                  let primary = document.printSelectedStrokeID ?? document.printSelectedTextID {
            let delta = target - document.printTransform(for: primary).rotation
            let origins = Dictionary(
                uniqueKeysWithValues: ids.map { ($0, document.printTransform(for: $0)) }
            )
            let centers = Dictionary(
                uniqueKeysWithValues: ids.compactMap { id -> (UUID, CGPoint)? in
                    let bounds = document.printBounds(for: id)
                    guard !bounds.isNull else { return nil }
                    return (id, CGPoint(x: bounds.midX, y: bounds.midY))
                }
            )
            document.rotatePrintSelection(
                by: delta,
                around: CGPoint(x: bbox.midX, y: bbox.midY),
                originTransforms: origins,
                originCenters: centers,
                recordUndo: false
            )
        }
        syncDegreesField()
        onChanged()
    }

    private func toggleFlip(horizontal: Bool) {
        guard !document.printSelectionIsEmpty else { return }
        document.beginInteractiveEdit()
        document.flipPrintSelection(horizontal: horizontal)
        onChanged()
    }
}
