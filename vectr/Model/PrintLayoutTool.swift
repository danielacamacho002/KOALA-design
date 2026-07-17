//
//  PrintLayoutTool.swift
//  vectr
//

import Foundation

enum PrintLayoutTool: String, CaseIterable, Codable {
    case select
    case printBorder

    var label: String {
        switch self {
        case .select: return "Select"
        case .printBorder: return "Print Border"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "arrow.up.and.down.and.arrow.left.and.right"
        case .printBorder: return "rectangle.dashed"
        }
    }
}
