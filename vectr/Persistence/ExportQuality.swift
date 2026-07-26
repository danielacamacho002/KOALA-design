//
//  ExportQuality.swift
//  vectr
//

import CoreGraphics
import Foundation

enum ExportQuality: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Longest edge of the rendered bitmap, in pixels.
    var longEdgePixels: CGFloat {
        switch self {
        case .low: return 1024
        case .medium: return 2048
        case .high: return 4096
        }
    }

    var jpegCompression: CGFloat {
        switch self {
        case .low: return 0.7
        case .medium: return 0.85
        case .high: return 0.92
        }
    }
}
