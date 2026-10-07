//
//  SystemColorPickerSheet.swift
//  Koala
//

import SwiftUI
import UIKit

/// Full system color picker (wheel, sliders, eyedropper) presented as a sheet
/// using the same dark menu colors as Settings and New Canvas.
struct SystemColorPickerSheet: View {
    @Binding var color: Color
    var onBeginEditing: (() -> Void)? = nil

    var body: some View {
        SystemColorPickerController(color: $color, onBeginEditing: onBeginEditing)
            .colorPickerMenuChrome()
    }
}

extension View {
    func colorPickerMenuChrome() -> some View {
        let page = Color(hex: AppearanceSettings.pasteboardHex)
        return background(SquareSheetCorners())
            .presentationBackground(page)
            .presentationCornerRadius(0)
            .preferredColorScheme(.dark)
    }
}

private struct SystemColorPickerController: UIViewControllerRepresentable {
    @Binding var color: Color
    var onBeginEditing: (() -> Void)?

    func makeUIViewController(context: Context) -> StyledColorPickerController {
        let picker = StyledColorPickerController()
        picker.delegate = context.coordinator
        picker.selectedColor = UIColor(color)
        picker.supportsAlpha = false
        ColorPickerMenuStyle.apply(to: picker)
        return picker
    }

    func updateUIViewController(_ picker: StyledColorPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color, onBeginEditing: onBeginEditing)
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        @Binding var color: Color
        private let onBeginEditing: (() -> Void)?
        private var hasBegunEditing = false

        init(color: Binding<Color>, onBeginEditing: (() -> Void)?) {
            _color = color
            self.onBeginEditing = onBeginEditing
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController,
            didSelect selectedColor: UIColor,
            continuously: Bool
        ) {
            if !hasBegunEditing {
                hasBegunEditing = true
                onBeginEditing?()
            }
            color = Color(selectedColor)
        }
    }
}

private final class StyledColorPickerController: UIColorPickerViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        ColorPickerMenuStyle.apply(to: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ColorPickerMenuStyle.apply(to: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ColorPickerMenuStyle.fitMenu(in: view)
    }
}

private enum ColorPickerMenuStyle {
    static func apply(to picker: UIColorPickerViewController) {
        let page = UIColor(Color(hex: AppearanceSettings.pasteboardHex))
        let card = UIColor(Color(hex: AppearanceSettings.toolbarHex))
        picker.overrideUserInterfaceStyle = .dark
        picker.view.backgroundColor = page
        picker.sheetPresentationController?.preferredCornerRadius = 0

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = page
        bar.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        picker.navigationItem.standardAppearance = bar
        picker.navigationItem.scrollEdgeAppearance = bar
        picker.navigationItem.compactAppearance = bar

        styleChrome(in: picker.view, page: page, card: card)
        fitMenu(in: picker.view)
    }

    /// Scales the whole color menu so its bottom stays on screen.
    static func fitMenu(in root: UIView) {
        let scale: CGFloat = 0.95
        let target = menuHost(in: root) ?? root
        guard abs(target.transform.a - scale) > 0.001 else { return }
        target.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    private static func menuHost(in root: UIView) -> UIView? {
        var found: UIView?
        func walk(_ view: UIView) {
            if found != nil { return }
            if view !== root {
                let viewName = NSStringFromClass(type(of: view))
                let layerName = NSStringFromClass(type(of: view.layer))
                if layerName.contains("Host")
                    || viewName.contains("SceneHosting")
                    || viewName.contains("RemoteView") {
                    found = view
                    return
                }
            }
            for subview in view.subviews {
                walk(subview)
            }
        }
        walk(root)
        return found
    }

    private static func styleChrome(in view: UIView, page: UIColor, card: UIColor) {
        if let bar = view as? UINavigationBar {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = page
            appearance.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.compactAppearance = appearance
            bar.tintColor = .secondaryLabel
        } else if view is UITableView || view is UICollectionView {
            view.backgroundColor = page
        } else if let effectView = view as? UIVisualEffectView {
            effectView.effect = nil
            effectView.contentView.backgroundColor = card
            effectView.backgroundColor = card
        }

        for subview in view.subviews {
            styleChrome(in: subview, page: page, card: card)
        }
    }
}
