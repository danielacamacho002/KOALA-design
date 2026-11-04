//
//  PatternPanelView.swift
//  Koala
//

import SwiftUI

struct PatternPanelView: View {
    @Bindable var document: KoalaDocument
    var units: MeasurementUnit
    @Binding var settings: PatternSettings
    var onPreviewChange: () -> Void
    var onApply: () -> Void
    var onCancel: () -> Void
    var onStatus: (String) -> Void

    private var canApply: Bool {
        guard document.selectedStrokeID != nil,
              let stroke = document.selectedStrokeID.flatMap({ document.stroke(with: $0) }),
              let layer = document.layers.first(where: { $0.id == stroke.layerID }),
              !layer.isLocked,
              let strokeID = document.selectedStrokeID else { return false }
        let application = PatternEngine.application(
            from: stroke,
            sourceID: strokeID,
            settings: settings
        )
        return application.repositionedSource != nil || !application.newStrokes.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelHeader("Pattern")

            ToolPanelJoinedActions(rows: [
                .init([
                    modeButton(.grid),
                    modeButton(.linear),
                ]),
                .init([
                    modeButton(.radial),
                    modeButton(.spiral),
                ]),
            ])

            modeControls

            if settings.mode == .radial || settings.mode == .spiral {
                Toggle("Keep original", isOn: $settings.keepOriginal)
                    .font(.caption2)
                    .onChange(of: settings.keepOriginal) { _, _ in onPreviewChange() }

                Toggle("Rotate copies", isOn: $settings.rotateCopies)
                    .font(.caption2)
                    .onChange(of: settings.rotateCopies) { _, _ in onPreviewChange() }
            }

            HStack(spacing: 4) {
                ToolPanelCancelButton { onCancel() }

                Spacer()

                ToolPanelApplyButton(isDisabled: !canApply) { apply() }
            }
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
        .onAppear {
            onPreviewChange()
        }
        .onChange(of: document.selectedStrokeID) { _, _ in
            if let id = document.selectedStrokeID,
               let stroke = document.stroke(with: id) {
                settings = PatternSettings.defaults(for: stroke)
            }
            onPreviewChange()
        }
    }

    private func modeButton(_ mode: PatternMode) -> ToolPanelJoinedActions.Item {
        .init(title: mode.label, prominent: settings.mode == mode) {
            guard settings.mode != mode else { return }
            settings.mode = mode
            onPreviewChange()
        }
    }

    @ViewBuilder
    private var modeControls: some View {
        switch settings.mode {
        case .grid:
            gridControls
        case .linear:
            linearControls
        case .radial:
            radialControls
        case .spiral:
            spiralControls
        }
    }

    private var gridControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            PatternIntStepperRow(label: "Rows", value: settings.rows) { value in
                settings.rows = value
                onPreviewChange()
            }
            PatternIntStepperRow(label: "Columns", value: settings.columns) { value in
                settings.columns = value
                onPreviewChange()
            }
            PatternLengthStepperRow(label: "Spacing X", value: settings.spacingX, units: units, minimum: 0) { value in
                settings.spacingX = value
                onPreviewChange()
            }
            PatternLengthStepperRow(label: "Spacing Y", value: settings.spacingY, units: units, minimum: 0) { value in
                settings.spacingY = value
                onPreviewChange()
            }
        }
    }

    private var linearControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            PatternIntStepperRow(label: "Count", value: settings.count) { value in
                settings.count = value
                onPreviewChange()
            }
            Picker("Direction", selection: $settings.linearDirection) {
                ForEach(LinearDirection.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
            .pickerStyle(.menu)
            .font(.caption2)
            .onChange(of: settings.linearDirection) { _, _ in onPreviewChange() }

            if settings.linearDirection == .horizontal {
                Toggle("Flip direction", isOn: $settings.flipLinearDirection)
                    .font(.caption2)
                    .onChange(of: settings.flipLinearDirection) { _, _ in onPreviewChange() }

                PatternLengthStepperRow(label: "Spacing X", value: settings.spacingX, units: units, minimum: 0) { value in
                    settings.spacingX = value
                    onPreviewChange()
                }
            } else {
                PatternLengthStepperRow(label: "Spacing Y", value: settings.spacingY, units: units, minimum: 0) { value in
                    settings.spacingY = value
                    onPreviewChange()
                }
            }
        }
    }

    private var radialControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            PatternIntStepperRow(label: "Count", value: settings.count) { value in
                settings.count = value
                onPreviewChange()
            }
            PatternLengthStepperRow(label: "Start radius", value: settings.startRadius, units: units, minimum: 0) { value in
                settings.startRadius = value
                onPreviewChange()
            }
            PatternLengthStepperRow(
                label: "Tightness",
                value: settings.tightness,
                units: units,
                minimum: 0,
                disabled: settings.radialSpreadEven
            ) { value in
                settings.tightness = value
                onPreviewChange()
            }
            Toggle("Spread even", isOn: $settings.radialSpreadEven)
                .font(.caption2)
                .onChange(of: settings.radialSpreadEven) { _, _ in onPreviewChange() }
        }
    }

    private var spiralControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            PatternIntStepperRow(label: "Count", value: settings.count) { value in
                settings.count = value
                onPreviewChange()
            }
            PatternLengthStepperRow(label: "Start radius", value: settings.startRadius, units: units, minimum: 0) { value in
                settings.startRadius = value
                onPreviewChange()
            }
            PatternLengthStepperRow(label: "Tightness", value: settings.tightness, units: units, minimum: 0) { value in
                settings.tightness = value
                onPreviewChange()
            }
        }
    }

    private func apply() {
        guard let strokeID = document.selectedStrokeID else {
            onStatus("Select a shape first")
            return
        }
        switch document.applyPattern(to: strokeID, settings: settings) {
        case .success(let created):
            onStatus("Created \(created) cop\(created == 1 ? "y" : "ies")")
            onApply()
        case .noSelection:
            onStatus("Select a shape first")
        case .layerLocked:
            onStatus("Layer is locked")
        case .nothingToCreate:
            onStatus("Nothing to create with these settings")
        }
    }
}

private struct PatternIntStepperRow: View {
    let label: String
    let value: Int
    var range: ClosedRange<Int> = 1...PatternSettings.maxCount
    let onChange: (Int) -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel(label)
            ToolPanelNumericStepper(
                text: $text,
                placeholder: "\(range.lowerBound)",
                keyboardType: .numberPad,
                onMinus: { applyValue(value - 1) },
                onPlus: { applyValue(value + 1) },
                onSubmit: commitText
            )
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, newValue in
            if Int(cleanedText) != newValue {
                text = "\(newValue)"
            }
        }
        .onChange(of: text) { _, _ in
            applyParsedText(reformat: false)
        }
    }

    private var cleanedText: String {
        text.trimmingCharacters(in: .whitespaces)
    }

    private func applyValue(_ newValue: Int) {
        let clamped = min(range.upperBound, max(range.lowerBound, newValue))
        if clamped != value {
            onChange(clamped)
        }
        text = "\(clamped)"
    }

    private func commitText() {
        applyParsedText(reformat: true)
    }

    private func applyParsedText(reformat: Bool) {
        guard let parsed = Int(cleanedText) else {
            if reformat {
                text = "\(value)"
            }
            return
        }
        if range.contains(parsed) {
            if parsed != value {
                onChange(parsed)
            }
            if reformat {
                text = "\(parsed)"
            }
        } else if reformat {
            applyValue(parsed)
        }
    }
}

private struct PatternLengthStepperRow: View {
    let label: String
    let value: CGFloat
    let units: MeasurementUnit
    var minimum: CGFloat = 0
    var disabled: Bool = false
    let onChange: (CGFloat) -> Void

    @State private var text = ""

    private var displayValue: Double {
        units.fromDocumentUnits(value)
    }

    private var minDisplay: Double {
        units.fromDocumentUnits(minimum)
    }

    private var lengthStep: Double {
        switch units {
        case .millimeters: return 0.5
        case .meters: return 0.001
        case .inches: return 0.05
        case .feet: return 0.01
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel(label)
            ToolPanelNumericStepper(
                text: $text,
                placeholder: formatted(minDisplay),
                unitLabel: units.shortLabel,
                onMinus: { applyDisplay(max(minDisplay, displayValue - lengthStep)) },
                onPlus: { applyDisplay(displayValue + lengthStep) },
                onSubmit: commitText
            )
            .disabled(disabled)
        }
        .opacity(disabled ? 0.55 : 1)
        .onAppear { syncText() }
        .onChange(of: value) { _, _ in
            if !textRepresents(displayValue) {
                syncText()
            }
        }
        .onChange(of: units) { _, _ in
            syncText()
        }
        .onChange(of: text) { _, _ in
            applyParsedText(reformat: false)
        }
    }

    private var cleanedText: String {
        text.replacingOccurrences(of: units.shortLabel, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func formatted(_ value: Double) -> String {
        units.formatted(value)
    }

    private func syncText() {
        text = formatted(displayValue)
    }

    private func textRepresents(_ display: Double) -> Bool {
        guard let parsed = Double(cleanedText) else { return false }
        return abs(parsed - display) < 0.0001
    }

    private func applyDisplay(_ display: Double) {
        let clamped = max(minDisplay, display)
        let documentValue = units.toDocumentUnits(clamped)
        if abs(documentValue - value) > 0.0001 {
            onChange(documentValue)
        }
        text = formatted(clamped)
    }

    private func commitText() {
        applyParsedText(reformat: true)
    }

    private func applyParsedText(reformat: Bool) {
        guard let parsed = Double(cleanedText) else {
            if reformat {
                syncText()
            }
            return
        }
        if parsed + 0.0001 >= minDisplay {
            let documentValue = units.toDocumentUnits(parsed)
            if abs(documentValue - value) > 0.0001 {
                onChange(documentValue)
            }
            if reformat {
                text = formatted(max(minDisplay, parsed))
            }
        } else if reformat {
            applyDisplay(parsed)
        }
    }
}
