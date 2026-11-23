//
//  CanvasSizeSheet.swift
//  Koala
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

    private static let selectableUnits: [MeasurementUnit] = MeasurementUnit.allCases

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
        return unit.formatted(value)
    }
}

/// Squares system sheet corners and drops the shadow that otherwise glows behind the menu.
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        squareOff()
        // The sheet installs its shadow image after the first layout pass.
        DispatchQueue.main.async { [weak self] in
            self?.squareOff()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        squareOff()
    }

    func squareOff() {
        var ancestor: UIViewController? = self
        while let current = ancestor {
            if let sheet = current.sheetPresentationController {
                if sheet.preferredCornerRadius != 0 {
                    sheet.preferredCornerRadius = 0
                }
                if let opacity = cgFloat(sheet, "_preferredShadowOpacity"), opacity != 0 {
                    setCGFloat(sheet, "_setPreferredShadowOpacity:", 0)
                }
                if let radius = cgFloat(sheet, "_shadowRadius"), radius != 0 {
                    setCGFloat(sheet, "_setShadowRadius:", 0)
                }
            }
            if let dropShadow = dropShadowView(from: current) {
                concealMagicShadow(on: dropShadow)
            }
            if let container = current.presentationController?.containerView {
                squareSheetChrome(container)
            }
            ancestor = current.parent
        }
    }

    /// The visible halo is `magicShadowView`, an image behind the sheet. Clearing
    /// `layer.shadowOpacity` leaves that image in place.
    private func concealMagicShadow(on dropShadow: UIView) {
        dropShadow.layer.cornerRadius = 0
        if dropShadow.responds(to: Selector(("magicShadowView"))),
           let magic = dropShadow.value(forKey: "magicShadowView") as? UIView {
            conceal(magic)
        }
        if let alpha = cgFloat(dropShadow, "magicShadowAlpha"), alpha != 0 {
            setCGFloat(dropShadow, "setMagicShadowAlpha:", 0)
        }
        for subview in dropShadow.subviews where isDecorativeShadow(subview) && !containsControllerView(subview) {
            conceal(subview)
        }
    }

    private func squareSheetChrome(_ container: UIView) {
        var view: UIView? = self.view
        while let current = view {
            if current.layer.cornerRadius != 0 {
                current.layer.cornerRadius = 0
            }
            if current === container { break }
            view = current.superview
        }
        concealDecorativeShadows(in: container, depth: 6)
    }

    private func concealDecorativeShadows(in view: UIView, depth: Int) {
        guard depth > 0 else { return }
        for subview in view.subviews {
            if isDecorativeShadow(subview) && !containsControllerView(subview) {
                conceal(subview)
            } else {
                concealDecorativeShadows(in: subview, depth: depth - 1)
            }
        }
    }

    private func conceal(_ view: UIView) {
        if view.alpha != 0 { view.alpha = 0 }
        if view.layer.opacity != 0 { view.layer.opacity = 0 }
    }

    private func dropShadowView(from controller: UIViewController) -> UIView? {
        let selector = Selector(("dropShadowView"))
        guard controller.responds(to: selector) else { return nil }
        return controller.value(forKey: "dropShadowView") as? UIView
    }

    private func isDecorativeShadow(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        return name.contains("Shadow") || name.contains("Glow")
    }

    private func containsControllerView(_ view: UIView) -> Bool {
        if view === self.view { return true }
        return view.subviews.contains { containsControllerView($0) }
    }

    private func cgFloat(_ object: NSObject, _ name: String) -> CGFloat? {
        let selector = Selector(name)
        guard object.responds(to: selector) else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector) -> CGFloat
        let implementation = object.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(object, selector)
    }

    private func setCGFloat(_ object: NSObject, _ name: String, _ value: CGFloat) {
        let selector = Selector(name)
        guard object.responds(to: selector) else { return }
        typealias Function = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        let implementation = object.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(object, selector, value)
    }
}
