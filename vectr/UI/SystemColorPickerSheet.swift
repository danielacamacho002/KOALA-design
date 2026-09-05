//
//  SystemColorPickerSheet.swift
//  vectr
//

import SwiftUI

/// Full system color picker (wheel, sliders, eyedropper) presented as a sheet.
struct SystemColorPickerSheet: UIViewControllerRepresentable {
    @Binding var color: Color
    var onBeginEditing: (() -> Void)?

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.delegate = context.coordinator
        picker.selectedColor = UIColor(color)
        picker.supportsAlpha = false
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {}

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
