//
//  CanvasSizeSheet.swift
//  vectr
//

import CoreGraphics
import SwiftUI
import UIKit

/// Prompt shown when creating a new canvas. Lets the user pick width, height, and
/// the unit those values are entered in. Leaving the fields blank falls back to the
/// default 24" × 18" canvas.
struct CanvasSizeSheet: View {
    /// Called with the resolved canvas size (in document points) and the chosen working unit.
    var onCreate: (CGSize, MeasurementUnit) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var widthText = ""
    @State private var heightText = ""
    @State private var unit: MeasurementUnit = .inches

    /// Units offered in the picker (inches default, plus centimeters and points).
    private static let selectableUnits: [MeasurementUnit] = [.inches, .centimeters, .points]

    private var defaultWidthDisplay: CGFloat {
        unit.fromDocumentUnits(DocumentSettings.defaultCanvasWidth)
    }

    private var defaultHeightDisplay: CGFloat {
        unit.fromDocumentUnits(DocumentSettings.defaultCanvasHeight)
    }

    private var pageColor: Color { Color(hex: AppearanceSettings.pasteboardHex) }
    private var cardColor: Color { Color(hex: AppearanceSettings.toolbarHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Canvas Size")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            dimensionRow(title: "Width", text: $widthText, placeholder: defaultWidthDisplay)
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 1)
                            dimensionRow(title: "Height", text: $heightText, placeholder: defaultHeightDisplay)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardColor)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Units")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        SettingsOptionBar(
                            options: Self.selectableUnits,
                            selection: $unit,
                            title: \.label
                        )
                        .background(cardColor)
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(pageColor)
            .navigationTitle("New Canvas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        create()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create")
                }
            }
        }
        .background(SquareSheetCorners())
        .presentationBackground(pageColor)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private func dimensionRow(title: String, text: Binding<String>, placeholder: CGFloat) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(formatted(placeholder), text: text)
                .textFieldStyle(.plain)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text(unit.shortLabel)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func create() {
        onCreate(resolvedSize(), unit)
        dismiss()
    }

    private func resolvedSize() -> CGSize {
        CGSize(
            width: resolvedDimension(text: widthText, defaultPoints: DocumentSettings.defaultCanvasWidth),
            height: resolvedDimension(text: heightText, defaultPoints: DocumentSettings.defaultCanvasHeight)
        )
    }

    private func resolvedDimension(text: String, defaultPoints: CGFloat) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0 else { return defaultPoints }
        let points = unit.toDocumentUnits(CGFloat(value))
        let maxPoints = DocumentSettings.maximumCanvasExtent(for: unit)
        return min(max(points, 1), maxPoints)
    }

    private func formatted(_ value: CGFloat) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

/// Clears the system sheet radius so the new-canvas menu has square corners.
struct SquareSheetCorners: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SquareSheetCornerController {
        SquareSheetCornerController()
    }

    func updateUIViewController(_ controller: SquareSheetCornerController, context: Context) {
        controller.squareOff()
    }
}

final class SquareSheetCornerController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        squareOff()
    }

    func squareOff() {
        var ancestor: UIViewController? = self
        while let current = ancestor {
            current.sheetPresentationController?.preferredCornerRadius = 0
            current.presentationController?.containerView?.layer.cornerRadius = 0
            ancestor = current.parent
        }

        var view: UIView? = self.view
        while let current = view {
            current.layer.cornerRadius = 0
            view = current.superview
        }
    }
}
