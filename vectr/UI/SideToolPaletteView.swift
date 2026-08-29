//
//  SideToolPaletteView.swift
//  vectr
//

import SwiftUI

struct SideToolPaletteView: View {
    @Bindable var document: VectrDocument
    var onToolSelected: (ToolCategory?) -> Void

    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ToolCategory.shapeCategories, id: \.self) { category in
                toolButton(category)
            }

            ToolPaletteSeparator()

            ForEach(ToolCategory.actionCategories, id: \.self) { category in
                toolButton(category)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private func toolButton(_ category: ToolCategory) -> some View {
        StudioIconButton(
            systemImage: category.systemImage,
            isActive: isToolHighlighted(category),
            size: iconSize,
            inactiveColor: .white
        ) {
            if document.activeCategory == category {
                // Move is the default tool — tapping it again stays on Move.
                guard category != .move else { return }
                document.clearActiveTool()
                onToolSelected(.move)
            } else {
                document.selectTool(category)
                onToolSelected(category)
            }
        }
        .accessibilityLabel(category.label)
    }

    /// Move is the idle default, so keep its icon quiet until there is a
    /// selection (or other tools, which highlight whenever they are active).
    private func isToolHighlighted(_ category: ToolCategory) -> Bool {
        guard document.activeCategory == category else { return false }
        if category == .move {
            return !document.selectionIsEmpty
        }
        return true
    }
}

/// Scale tool options, presented as a left-aligned command panel matching the
/// other drawing tools (uniform vs. free scaling).
struct ScaleToolPanelView: View {
    @Bindable var document: VectrDocument
    var onVariantSelected: () -> Void

    private let options = ["Uniform", "Free"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelHeader("Scale")

            VStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                    ToolPanelLabelButton(
                        title: label,
                        prominent: index == selectedIndex,
                        fullWidth: true,
                        alignment: .leading
                    ) {
                        document.scaleUniform = index == 0
                        onVariantSelected()
                    }
                }
            }
        }
        .toolPanelChrome(width: 150)
    }

    private var selectedIndex: Int {
        document.scaleUniform ? 0 : 1
    }
}

struct ToolPaletteSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}
