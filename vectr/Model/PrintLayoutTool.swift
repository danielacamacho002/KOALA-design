//
//  PrintLayoutTool.swift
//  vectr
//

import Foundation

enum PrintLayoutTool: String, CaseIterable, Codable {
    case select
    case cut

    var label: String {
        switch self {
        case .select: return "Select"
        case .cut: return "Cut"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "arrow.up.and.down.and.arrow.left.and.right"
        case .cut: return "scissors"
        }
    }
}
