//
//  TextToolPanelView.swift
//  Koala
//

import SwiftUI

/// Floating panel for entering and editing a text element's content, size,
/// color, stroke weight, and outline (hollow) mode.
struct TextToolPanelView: View {
    @Bindable var document: KoalaDocument
    let elementID: UUID
    var onChanged: () -> Void
    var onDone: () -> Void

    @State private var text: String = ""
    @State private var showFillPicker = false
    @State private var showStrokePicker = false
    @FocusState private var focused: Bool

    private static let strokeRange: ClosedRange<CGFloat> = 0.5...48
    private static let strokeStep: CGFloat = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Text")
                Spacer()
                ToolPanelApplyButton(action: onDone)
            }

            TextField(
                "",
                text: $text,
                prompt: Text("Type here").foregroundStyle(Color.white.opacity(0.45)),
                axis: .vertical
            )
                .font(.system(size: 13))
                .foregroundStyle(Color.toolPanelButtonForeground)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .toolPanelControlFill()
                .onChange(of: text) { _, newValue in
                    applyText(newValue)
                }

            HStack(spacing: 10) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(Color.toolPanelSecondaryLabel)
                Slider(value: fontSizeBinding, in: 6...200, step: 1)
                Text("\(Int(currentFontSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }

            ToolPanelDivider()

            Toggle(isOn: outlineBinding) {
                Text("Outline")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)

            colorRow(
                label: "Fill",
                swatch: currentFillColor,
                accessibility: "Fill color"
            ) { showFillPicker = true }
            .sheet(isPresented: $showFillPicker) {
                TextColorPickerSheet(color: fillColorBinding)
            }

            colorRow(
                label: "Stroke",
                swatch: currentStrokeColor,
                accessibility: "Stroke color"
            ) { showStrokePicker = true }
            .sheet(isPresented: $showStrokePicker) {
                TextColorPickerSheet(color: strokeColorBinding)
            }

            strokeWeightRow
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
        .onAppear {
            text = document.textElement(with: elementID)?.text ?? ""
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: elementID) { _, _ in
            text = document.textElement(with: elementID)?.text ?? ""
        }
    }

    // MARK: - Element accessors

    private var element: TextElement? {
        document.textElement(with: elementID)
    }

    private var currentFontSize: CGFloat {
        element?.fontSize ?? document.activeFontSize
    }

    private var currentFillColor: Color {
        (element?.color ?? CodableColor(.primary)).color
    }

    private var currentStrokeColor: Color {
        (element?.strokeColor ?? CodableColor(.primary)).color
    }

    private var currentStrokeWidth: CGFloat {
        element?.strokeWidth ?? TextElement.defaultStrokeWidth
    }

    // MARK: - Bindings

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(currentFontSize) },
            set: { newValue in
                document.activeFontSize = CGFloat(newValue)
                document.setTextFontSize(id: elementID, size: CGFloat(newValue))
                onChanged()
            }
        )
    }

    private var outlineBinding: Binding<Bool> {
        Binding(
            get: { element?.isOutline ?? false },
            set: { newValue in
                document.setTextOutline(id: elementID, isOutline: newValue, recordUndo: true)
                onChanged()
            }
        )
    }

    private var fillColorBinding: Binding<Color> {
        Binding(
            get: { currentFillColor },
            set: { newValue in
                document.setTextFillColor(id: elementID, color: CodableColor(newValue))
                onChanged()
            }
        )
    }

    private var strokeColorBinding: Binding<Color> {
        Binding(
            get: { currentStrokeColor },
            set: { newValue in
                document.setTextStrokeColor(id: elementID, color: CodableColor(newValue))
                onChanged()
            }
        )
    }

    // MARK: - Rows

    private func colorRow(
        label: String,
        swatch: Color,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ToolPanelSectionLabel(label)
                .frame(width: 44, alignment: .leading)

            Rectangle()
                .fill(swatch)
                .frame(width: 26, height: 26)
                .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))

            Button(action: action) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: "BBD159"))
                    .frame(width: 24, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibility)

            Spacer()
        }
    }

    private var strokeWeightRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Stroke Weight")

            HStack(spacing: 6) {
                ToolPanelIconButton(systemImage: "minus") {
                    setStrokeWidth(currentStrokeWidth - Self.strokeStep)
                }

                Text(strokeWidthLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.toolPanelButtonForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .toolPanelControlFill()

                ToolPanelIconButton(systemImage: "plus") {
                    setStrokeWidth(currentStrokeWidth + Self.strokeStep)
                }
            }
        }
    }

    private var strokeWidthLabel: String {
        let width = currentStrokeWidth
        if width.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f pt", width)
        }
        return String(format: "%.1f pt", width)
    }

    // MARK: - Actions

    private func setStrokeWidth(_ proposed: CGFloat) {
        let clamped = min(Self.strokeRange.upperBound, max(Self.strokeRange.lowerBound, proposed))
        document.setTextStrokeWidth(id: elementID, width: clamped)
        onChanged()
    }

    private func applyText(_ newValue: String) {
        guard var element = document.textElement(with: elementID) else { return }
        element.text = newValue
        document.updateTextElement(element, recordUndo: false)
        onChanged()
    }
}

/// Full system color picker, styled like Settings and New Canvas.
private struct TextColorPickerSheet: View {
    @Binding var color: Color

    var body: some View {
        SystemColorPickerSheet(color: $color)
    }
}
