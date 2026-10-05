//
//  EditorToolbarView.swift
//  vectr
//

import SwiftUI

struct EditorToolbarView: View {
    @Bindable var document: VectrDocument
    var canUndo: Bool
    var canRedo: Bool
    var onBack: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onSettings: () -> Void
    var onShare: () -> Void
    var onSave: () -> Void
    var onToolSelected: (ToolCategory?) -> Void
    var onSwitchToPrintLayout: (() -> Void)?
    var highlightedTarget: OnboardingTarget? = nil
    var onVisibilityToggled: () -> Void

    static let height: CGFloat = 48
    private var toolbarHeight: CGFloat { Self.height }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: toolbarHeight)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            ToolPaletteSeparator()
                .padding(.horizontal, 12)

            SideToolPaletteView(
                document: document,
                onToolSelected: onToolSelected,
                highlightedTarget: highlightedTarget
            )

            Spacer(minLength: 16)

            HStack(spacing: 4) {
                toolbarIconButton("arrow.uturn.backward", disabled: !canUndo, action: onUndo)
                toolbarIconButton("arrow.uturn.forward", disabled: !canRedo, action: onRedo)
                toolbarIconButton(
                    document.visibilityToolbarImage,
                    disabled: !document.canToggleElementVisibility,
                    action: {
                        document.toggleSelectedElementsHidden()
                        onVisibilityToggled()
                    },
                    accessibilityLabel: document.visibilityToolbarAccessibilityLabel
                )
            }

            ToolPaletteSeparator()
                .padding(.horizontal, 10)

            HStack(spacing: 4) {
                toolbarIconButton("gearshape", action: onSettings, accessibilityLabel: "Settings")
                if let onSwitchToPrintLayout {
                    toolbarIconButton(
                        "rectangle.split.3x3",
                        action: onSwitchToPrintLayout,
                        accessibilityLabel: "Print Layout",
                        onboardingTarget: .printLayout
                    )
                }
                toolbarIconButton(
                    "square.and.arrow.up",
                    action: onShare,
                    accessibilityLabel: "Share",
                    onboardingTarget: .share
                )
                toolbarIconButton(
                    "square.and.arrow.down",
                    action: onSave,
                    accessibilityLabel: "Save",
                    onboardingTarget: .save
                )
            }
        }
        .frame(height: toolbarHeight)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: AppearanceSettings.toolbarHex))
    }

    private func toolbarIconButton(
        _ systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void,
        accessibilityLabel: String? = nil,
        onboardingTarget: OnboardingTarget? = nil
    ) -> some View {
        let isHighlighted = onboardingTarget != nil && highlightedTarget == onboardingTarget
        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 36, height: toolbarHeight)
                .foregroundStyle(disabled ? Color.white.opacity(0.3) : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
        .modifier(OnboardingTargetChrome(target: onboardingTarget, isHighlighted: isHighlighted))
    }
}
