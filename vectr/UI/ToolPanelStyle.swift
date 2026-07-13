//
//  ToolPanelStyle.swift
//  vectr
//
//  Shared visual language for the floating tool command panels so drawing and
//  manipulation tools stay consistent. Modeled on the shape command panel look:
//  sharp-cornered chrome, custom square icon buttons, and monospaced inputs.
//

import SwiftUI

extension View {
    /// Applies the standard tool panel chrome: sharp rectangle fill with a hairline
    /// stroke and consistent padding.
    func toolPanelChrome(width: CGFloat? = nil) -> some View {
        self
            .padding(8)
            .frame(width: width)
            .background(Rectangle().fill(Color(.systemBackground).opacity(0.92)))
            .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

/// Panel title, e.g. "Rotate", "Fillet".
struct ToolPanelHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
    }
}

/// Small secondary label used above a control group, e.g. "Thickness", "Color".
struct ToolPanelSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}

/// Square icon button matching the shape command panel's controls.
struct ToolPanelIconButton: View {
    let systemImage: String
    var prominent: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(width: 26, height: 26)
                .background(prominent ? Color.accentColor : Color(.systemGray))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}

/// Standard "cancel / clear" control shared by every tool panel.
struct ToolPanelCancelButton: View {
    let action: () -> Void

    var body: some View {
        ToolPanelIconButton(systemImage: "xmark", action: action)
            .accessibilityLabel("Cancel")
    }
}

/// Standard "apply / confirm" control shared by every tool panel.
struct ToolPanelApplyButton: View {
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        ToolPanelIconButton(
            systemImage: "checkmark",
            prominent: true,
            isDisabled: isDisabled,
            action: action
        )
        .accessibilityLabel("Apply")
    }
}

/// Text button matching the shape command panel's variant/action controls.
struct ToolPanelLabelButton: View {
    let title: String
    var prominent: Bool = false
    var isDisabled: Bool = false
    var fullWidth: Bool = false
    var alignment: Alignment = .center
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(maxWidth: fullWidth ? .infinity : nil, alignment: alignment)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(prominent ? Color.accentColor : Color(.systemGray))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}
