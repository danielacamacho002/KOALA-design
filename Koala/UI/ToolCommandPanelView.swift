//
//  ToolCommandPanelView.swift
//  Koala
//

import SwiftUI

struct ToolCommandPanelView: View {
    @Bindable var session: ShapeCommandSession
    @Bindable var document: KoalaDocument
    var units: MeasurementUnit
    var grid: GridSettings
    var documentSettings: DocumentSettings
    var snapEnabled: Bool
    var onSubmitPoint: () -> Void
    var onDone: () -> Void
    var onCancel: () -> Void
    var onVariantChanged: () -> Void
    var isTourHighlighted: Bool = false

    private let panelWidth = ToolPanelMetrics.commandWidth
    /// Thickness step in document points so behavior matches the select/move panel.
    private static let thicknessStepPoints: CGFloat = 0.5

    @State private var thicknessText = ""
    @State private var showColorPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    panelHeader
                    variantSection
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.prompt)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.toolPanelSecondaryLabel)

                    FingerOnlyTextField(
                        placeholder: inputPlaceholder,
                        text: $session.inputText,
                        keyboardType: .numbersAndPunctuation,
                        fontSize: 12,
                        cornerRadius: 0,
                        backgroundColor: .clear,
                        onSubmit: submitInput
                    )
                    .padding(.horizontal, 6)
                    .frame(width: ToolPanelMetrics.pointFieldWidth, height: 28, alignment: .leading)
                    .toolPanelControlFill()

                    if let error = session.lastError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let placed = session.placedPointsLabel(units: units) {
                        Text(placed)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.toolPanelSecondaryLabel)
                    }
                }

                thicknessSection
                colorRow
            }

            HStack {
                Spacer()

                ToolPanelCancelButton {
                    session.cancel()
                    onCancel()
                }
            }
        }
        .toolPanelChrome(width: panelWidth)
        .onboardingAnchor(.commandPanel)
        .onboardingHighlight(isTourHighlighted, cornerRadius: 0)
        .onAppear { syncThicknessText() }
        .onChange(of: document.strokeWidth) { _, _ in syncThicknessText() }
        .onChange(of: units) { _, _ in syncThicknessText() }
    }

    private var panelHeader: some View {
        ToolPanelSectionLabel(session.toolTitle)
    }

    // MARK: - Tool variant

    @ViewBuilder
    private var variantSection: some View {
        let options = variantOptions
        if !options.isEmpty {
            ToolPanelSegmentBar(
                options: options,
                selectedIndex: selectedVariantIndex,
                action: applyVariant
            )
            // Chrome pads the panel by 8; pull the variant bar out so it
            // sits 2pt from both edges.
            .padding(.horizontal, -6)
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
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Thickness")

            ToolPanelNumericStepper(
                text: $thicknessText,
                placeholder: "0",
                unitLabel: units.shortLabel,
                onMinus: { stepThickness(by: -Self.thicknessStepPoints) },
                onPlus: { stepThickness(by: Self.thicknessStepPoints) },
                onSubmit: applyThickness
            )
        }
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

            HStack(spacing: 2) {
                Rectangle()
                    .fill(document.strokeColor.color)
                    .frame(width: 26, height: 26)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))

                Button {
                    showColorPicker = true
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
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

    private var inputPlaceholder: String {
        session.controlPoints.isEmpty ? "x, y" : "x,y or d°"
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
