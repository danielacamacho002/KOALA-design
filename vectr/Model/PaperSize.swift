//
//  PaperSize.swift
//  vectr
//

import CoreGraphics
import Foundation

enum PaperSize: String, Codable, CaseIterable, Identifiable {
    case letter
    case a4
    case legal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .letter: return "Letter"
        case .a4: return "A4"
        case .legal: return "Legal"
        }
    }

    /// Size in document points (72 pt = 1 inch).
    var sizeInPoints: CGSize {
        switch self {
        case .letter: return CGSize(width: 612, height: 792)
        case .a4: return CGSize(width: 595, height: 842)
        case .legal: return CGSize(width: 612, height: 1008)
        }
    }
}
