//
//  FingerOnlyTextField.swift
//  vectr
//

import SwiftUI
import UIKit

private final class FingerOnlyUITextField: UITextField {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        if let touches = event?.allTouches {
            for touch in touches where touch.type == .pencil || touch.type == .stylus {
                return nil
            }
        }
        return super.hitTest(point, with: event)
    }
}

/// Text field that accepts finger/keyboard input only — Apple Pencil taps pass through.
struct FingerOnlyTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var onSubmit: (() -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let field = FingerOnlyUITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.font = UIFont.monospacedSystemFont(ofSize: UIFont.labelFontSize, weight: .regular)
        field.borderStyle = .none
        field.backgroundColor = .secondarySystemBackground
        field.layer.cornerRadius = 8
        field.keyboardType = keyboardType
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.keyboardType = keyboardType
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
        }

        @objc func textChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            onSubmit?()
            return true
        }
    }
}
