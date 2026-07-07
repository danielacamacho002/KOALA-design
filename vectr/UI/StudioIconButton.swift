//
//  StudioIconButton.swift
//  vectr
//

import SwiftUI

/// Procreate-style minimal tool control — icon only, no panel chrome.
struct StudioIconButton: View {
    let systemImage: String
    var isActive: Bool = false
    var size: CGFloat = 44
    var showsSubmenu: Bool = false
    var inactiveColor: Color = Color.primary.opacity(0.72)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: size, height: size)
                    .foregroundStyle(isActive ? Color.accentColor : inactiveColor)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.16))
                                .frame(width: size - 2, height: size - 2)
                        }
                    }

                if showsSubmenu {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(isActive ? Color.accentColor : inactiveColor.opacity(0.62))
                        .offset(x: -3, y: -3)
                }
            }
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
                .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.85))
                .background(
                    Capsule()
                        .fill(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}
