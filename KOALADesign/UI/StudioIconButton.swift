//
//  StudioIconButton.swift
//  Koala
//

import SwiftUI

/// Procreate-style minimal tool control — icon only, no panel chrome.
struct StudioIconButton: View {
    var isActive: Bool = false
    var size: CGFloat = 44
    var showsSubmenu: Bool = false
    var inactiveColor: Color = Color.primary.opacity(0.72)
    var action: () -> Void
    private let icon: AnyView

    init(
        systemImage: String,
        isActive: Bool = false,
        size: CGFloat = 44,
        showsSubmenu: Bool = false,
        inactiveColor: Color = Color.primary.opacity(0.72),
        action: @escaping () -> Void
    ) {
        self.isActive = isActive
        self.size = size
        self.showsSubmenu = showsSubmenu
        self.inactiveColor = inactiveColor
        self.action = action
        self.icon = AnyView(
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                .symbolRenderingMode(.monochrome)
        )
    }

    init<Icon: View>(
        isActive: Bool = false,
        size: CGFloat = 44,
        showsSubmenu: Bool = false,
        inactiveColor: Color = Color.primary.opacity(0.72),
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.isActive = isActive
        self.size = size
        self.showsSubmenu = showsSubmenu
        self.inactiveColor = inactiveColor
        self.action = action
        self.icon = AnyView(icon())
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                icon
                    .foregroundStyle(isActive ? SelectionHighlight.icon : inactiveColor)
                    .frame(width: size, height: size)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SelectionHighlight.background)
                                .frame(width: size - 2, height: size - 2)
                        }
                    }

                if showsSubmenu {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(isActive ? SelectionHighlight.icon : inactiveColor.opacity(0.62))
                        .offset(x: -3, y: -3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StudioTextChip: View {
    let title: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isActive ? SelectionHighlight.font : Color.primary.opacity(0.85))
                .background(
                    Capsule()
                        .fill(isActive ? SelectionHighlight.background : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}
