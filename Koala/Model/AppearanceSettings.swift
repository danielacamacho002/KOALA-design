//
//  AppearanceSettings.swift
//  Koala
//

import SwiftUI

/// App-wide appearance preferences persisted in UserDefaults.
enum AppearanceSettings {
    static let canvasColorKey = "appearance.canvasColorHex"

    static let defaultCanvasHex = "F6F3E4"

    static let canvasPresets: [String] = ["F6F3E4", "FEFDF7"]

    /// Fixed panel color (not user-configurable).
    static let panelHex = "DDDCD5"

    /// Fixed toolbar color (not user-configurable).
    static let toolbarHex = "4D4D4D"

    /// Dark grey "pasteboard" shown around the canvas sheet when zoomed out.
    static let pasteboardHex = "3A3A3A"
}

extension Color {
    /// Creates a color from a hex string (`RRGGBB` or `RRGGBBAA`, `#` optional).
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let r, g, b, a: UInt64
        switch sanitized.count {
        case 8:
            (r, g, b, a) = (value >> 24 & 0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            (r, g, b, a) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Uppercased `RRGGBB` hex representation.
    var hexString: String {
        let components = CodableColor(self)
        let r = Int((components.red * 255).rounded())
        let g = Int((components.green * 255).rounded())
        let b = Int((components.blue * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
