//
//  ToolCommandPanelView.swift
//  vectr
//

import SwiftUI

struct ToolCommandPanelView: View {
    @Bindable var session: ShapeCommandSession
    @Binding var dragOffset: CGSize
    var containerSize: CGSize
    var units: MeasurementUnit
    var grid: GridSettings
    var documentSettings: DocumentSettings
    var snapEnabled: Bool
    var onSubmitPoint: () -> Void
    var onDone: () -> Void
    var onCancel: () -> Void

    private let panelWidth: CGFloat = 172

    @State private var dragStartOffset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader

            Text(session.prompt)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 6) {
                FingerOnlyTextField(
                    placeholder: inputPlaceholder,
                    text: $session.inputText,
                    keyboardType: .numbersAndPunctuation,
                    onSubmit: submitInput
                )
                .frame(height: 36)

                Button(action: submitInput) {
                    Image(systemName: "return")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text(session.inputHint(units: units))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = session.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if let placed = session.placedPointsLabel(units: units) {
                Text(placed)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Cancel", role: .cancel) {
                    session.cancel()
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!session.canFinish)
            }
        }
        .padding(10)
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0.1), radius: isDragging ? 10 : 6, y: 3)
        .scaleEffect(isDragging ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .offset(dragOffset)
    }

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 14)

            Text(session.toolTitle)
                .font(.caption.weight(.semibold))

            Spacer()

            Text("\(session.controlPoints.count)/\(session.requiredPoints)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .gesture(panelDragGesture)
        .accessibilityLabel("Drag to reposition command panel")
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDragging {
                    dragStartOffset = dragOffset
                    isDragging = true
                }
                dragOffset = clampedOffset(
                    CGSize(
                        width: dragStartOffset.width + value.translation.width,
                        height: dragStartOffset.height + value.translation.height
                    )
                )
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        let margin: CGFloat = 8
        let panelHeight: CGFloat = 220
        let minX = margin
        let maxX = max(minX, containerSize.width - panelWidth - margin)
        let minY = margin
        let maxY = max(minY, containerSize.height - panelHeight - margin)
        return CGSize(
            width: min(max(proposed.width, minX), maxX),
            height: min(max(proposed.height, minY), maxY)
        )
    }

    private var inputPlaceholder: String {
        session.controlPoints.isEmpty ? "x, y" : "x, y or d °"
    }

    private func submitInput() {
        guard session.submit(
            units: units,
            grid: grid,
            documentSettings: documentSettings,
            snapEnabled: snapEnabled
        ) else { return }
        onSubmitPoint()
    }
}

extension ShapeCommandSession {
    func inputHint(units: MeasurementUnit) -> String {
        let u = units.shortLabel
        if controlPoints.isEmpty {
            return "Enter x, y in \(u) — e.g. 0,0 or 50,30"
        }

        if category == .circle, circleVariant == .center, controlPoints.count == 1 {
            return "Radius: 50 · Diameter: d100 · Polar: 50 90"
        }
        if category == .circle, circleVariant == .ellipse {
            if controlPoints.count == 1 {
                return "Enter horizontal radius rx — e.g. 40"
            }
            return "Enter vertical radius ry — e.g. 25"
        }
        if category == .rectangle, rectangleVariant == .center {
            if controlPoints.count == 1 {
                return "Half-width distance — e.g. 50"
            }
            return "Half-height distance — e.g. 30"
        }

        return "Absolute x, y · relative @dx,dy · polar: 15 90"
    }

    func placedPointsLabel(units: MeasurementUnit) -> String? {
        guard let last = controlPoints.last else { return nil }
        let x = units.fromDocumentUnits(last.x)
        let y = units.fromDocumentUnits(last.y)
        return String(format: "Placed: %.1f, %.1f %@", x, y, units.shortLabel)
    }
}
