//
//  ToolPanelStyle.swift
//  vectr
//
//  Shared visual language for the floating tool command panels so drawing and
//  manipulation tools stay consistent. Modeled on the shape command panel look:
//  sharp-cornered chrome, custom square icon buttons, and monospaced inputs.
//

import SwiftUI

extension Color {
    /// Fill for the non-prominent (secondary) tool panel buttons.
    static let toolPanelButtonFill = Color(hex: "F2F2F7")

    /// Foreground for content sitting on a non-prominent tool panel button.
    static let toolPanelButtonForeground = Color.black
}

extension View {
    /// Applies the standard tool panel chrome: sharp rectangle fill with a hairline
    /// stroke and consistent padding. Defaults to the shared panel color so every
    /// tool panel (shape, manipulation, dropdowns) stays unified.
    func toolPanelChrome(width: CGFloat? = nil, fill: Color? = nil) -> some View {
        modifier(ToolPanelChrome(width: width, fillOverride: fill))
    }
}

/// Shared chrome for floating tool panels.
private struct ToolPanelChrome: ViewModifier {
    var width: CGFloat?
    var fillOverride: Color?

    func body(content: Content) -> some View {
        content
            .padding(8)
            .frame(width: width)
            .background(Rectangle().fill(fillOverride ?? Color(hex: AppearanceSettings.panelHex)))
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
                .foregroundStyle(prominent ? Color.black : Color.toolPanelButtonForeground)
                .frame(width: 26, height: 26)
                .background(prominent ? Color.accentColor : Color.toolPanelButtonFill)
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
    var fill: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent ? Color.black : Color.toolPanelButtonForeground)
                .frame(maxWidth: fullWidth ? .infinity : nil, alignment: alignment)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(fill ?? (prominent ? Color.accentColor : Color.toolPanelButtonFill))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}
