//
//  ToolCommandPanelView.swift
//  vectr
//

import SwiftUI

struct ToolCommandPanelView: View {
    @Bindable var session: ShapeCommandSession
    @Bindable var document: VectrDocument
    var units: MeasurementUnit
    var grid: GridSettings
    var documentSettings: DocumentSettings
    var snapEnabled: Bool
    var onSubmitPoint: () -> Void
    var onDone: () -> Void
    var onCancel: () -> Void
    var onVariantChanged: () -> Void

    private let panelWidth: CGFloat = 150
    /// Thickness step in document points so behavior matches the select/move panel.
    private static let thicknessStepPoints: CGFloat = 0.5

    @State private var thicknessText = ""
    @State private var showColorPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader

            variantSection

            Text(session.prompt)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            FingerOnlyTextField(
                placeholder: inputPlaceholder,
                text: $session.inputText,
                keyboardType: .numbersAndPunctuation,
                fontSize: 13,
                cornerRadius: 0,
                onSubmit: submitInput
            )
            .frame(height: 30)

            if let error = session.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let placed = session.placedPointsLabel(units: units) {
                Text(placed)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            thicknessSection
            colorRow

            HStack {
                ToolPanelCancelButton {
                    session.cancel()
                    onCancel()
                }

                Spacer()
            }
        }
        .toolPanelChrome(width: panelWidth)
        .onAppear { syncThicknessText() }
        .onChange(of: document.strokeWidth) { _, _ in syncThicknessText() }
        .onChange(of: units) { _, _ in syncThicknessText() }
    }

    private var panelHeader: some View {
        ToolPanelHeader(session.toolTitle)
    }

    // MARK: - Tool variant

    @ViewBuilder
    private var variantSection: some View {
        let options = variantOptions
        if !options.isEmpty {
            VStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                    ToolPanelLabelButton(
                        title: label,
                        prominent: index == selectedVariantIndex,
                        fullWidth: true,
                        alignment: .leading
                    ) {
                        applyVariant(index: index)
                    }
                }
            }
        }
    }

    private var variantOptions: [String] {
        switch document.activeCategory {
        case .line: LineVariant.allCases.map(\.label)
        case .circle: CircleVariant.allCases.map(\.label)
        case .rectangle: RectangleVariant.allCases.map(\.label)
        default: []
        }
    }

    private var selectedVariantIndex: Int {
        switch document.activeCategory {
        case .line: LineVariant.allCases.firstIndex(of: document.lineVariant) ?? 0
        case .circle: CircleVariant.allCases.firstIndex(of: document.circleVariant) ?? 0
        case .rectangle: RectangleVariant.allCases.firstIndex(of: document.rectangleVariant) ?? 0
        default: 0
        }
    }

    private func applyVariant(index: Int) {
        switch document.activeCategory {
        case .line: document.lineVariant = LineVariant.allCases[index]
        case .circle: document.circleVariant = CircleVariant.allCases[index]
        case .rectangle: document.rectangleVariant = RectangleVariant.allCases[index]
        default: return
        }
        onVariantChanged()
    }

    // MARK: - Line thickness

    @ViewBuilder
    private var thicknessSection: some View {
        ToolPanelHeader("Thickness")

        HStack(spacing: 4) {
            Text("Current:")
            Text(currentThicknessText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            ToolPanelIconButton(systemImage: "minus") {
                stepThickness(by: -Self.thicknessStepPoints)
            }

            FingerOnlyTextField(
                placeholder: units.shortLabel,
                text: $thicknessText,
                keyboardType: .decimalPad,
                fontSize: 12,
                cornerRadius: 0,
                onSubmit: applyThickness
            )
            .frame(height: 28)

            ToolPanelIconButton(systemImage: "plus") {
                stepThickness(by: Self.thicknessStepPoints)
            }
        }

        ToolPanelLabelButton(title: "Apply", fullWidth: true) {
            applyThickness()
        }
    }

    private var currentThicknessText: String {
        "\(displayString(units.fromDocumentUnits(document.strokeWidth))) \(units.shortLabel)"
    }

    /// Formats a display-unit value with just enough precision (tiny units like inches need more).
    private func displayString(_ value: CGFloat) -> String {
        var text = String(format: "%.4f", value)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text.isEmpty ? "0" : text
    }

    private func syncThicknessText() {
        thicknessText = displayString(units.fromDocumentUnits(document.strokeWidth))
    }

    private func applyThickness() {
        let cleaned = thicknessText
            .replacingOccurrences(of: units.shortLabel, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else {
            syncThicknessText()
            return
        }
        document.strokeWidth = max(0.1, units.toDocumentUnits(CGFloat(value)))
        syncThicknessText()
    }

    private func stepThickness(by deltaDocPoints: CGFloat) {
        document.strokeWidth = max(0.1, document.strokeWidth + deltaDocPoints)
        syncThicknessText()
    }

    // MARK: - Line color

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Color")

            HStack(spacing: 8) {
                Rectangle()
                    .fill(document.strokeColor.color)
                    .frame(width: 26, height: 26)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))

                Button {
                    showColorPicker = true
                } label: {
                    colorWheel
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Line color")
                .sheet(isPresented: $showColorPicker) {
                    SystemColorPickerSheet(
                        color: Binding(
                            get: { document.strokeColor.color },
                            set: { document.strokeColor = CodableColor($0) }
                        )
                    )
                }
            }
        }
    }

    private var colorWheel: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: (0...12).map { Color(hue: Double($0) / 12.0, saturation: 0.85, brightness: 0.95) },
                    center: .center
                )
            )
            .overlay(
                Circle().fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.85), Color.white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 14
                    )
                )
            )
    }

    private var inputPlaceholder: String {
        session.controlPoints.isEmpty ? "x, y" : "x, y or d °"
    }

    private func submitInput() {
        // Return on an empty field finishes shapes that don't auto-commit (arc, center rectangle).
        if session.inputText.trimmingCharacters(in: .whitespaces).isEmpty {
            if session.canFinish { onDone() }
            return
        }
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
    func placedPointsLabel(units: MeasurementUnit) -> String? {
        guard let last = controlPoints.last else { return nil }
        let x = units.fromDocumentUnits(last.x)
        let y = units.fromDocumentUnits(last.y)
        return String(format: "Placed: %.1f, %.1f %@", x, y, units.shortLabel)
    }
}
