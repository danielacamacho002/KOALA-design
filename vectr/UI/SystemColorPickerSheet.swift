//
//  SystemColorPickerSheet.swift
//  vectr
//

import SwiftUI

private enum ColorPickerLayout {
    /// Compact popover size so grid cells stay small enough for the preview well.
    static let compactSize = CGSize(width: 390, height: 640)
}

extension View {
    /// Presents the system color picker as a compact popover so the color grid
    /// stays small enough that the selected-color well is on-screen.
    func systemColorPicker(
        isPresented: Binding<Bool>,
        color: Binding<Color>,
        onBeginEditing: (() -> Void)? = nil
    ) -> some View {
        popover(isPresented: isPresented) {
            SystemColorPickerSheet(color: color, onBeginEditing: onBeginEditing)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Compact system color picker (wheel, sliders, eyedropper).
///
/// A full iPad form sheet stretches the color grid until the preview well is
/// clipped or scrolled off. This width keeps the cells smaller so the well fits.
private struct SystemColorPickerSheet: View {
    @Binding var color: Color
    var onBeginEditing: (() -> Void)?

    var body: some View {
        SystemColorPickerController(color: $color, onBeginEditing: onBeginEditing)
            .frame(width: ColorPickerLayout.compactSize.width, height: ColorPickerLayout.compactSize.height)
    }
}

private struct SystemColorPickerController: UIViewControllerRepresentable {
    @Binding var color: Color
    var onBeginEditing: (() -> Void)?

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.delegate = context.coordinator
        picker.selectedColor = UIColor(color)
        picker.supportsAlpha = false
        picker.preferredContentSize = ColorPickerLayout.compactSize
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {}

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: UIColorPickerViewController,
        context: Context
    ) -> CGSize? {
        ColorPickerLayout.compactSize
    }

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
