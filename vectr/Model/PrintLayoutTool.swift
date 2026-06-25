//
//  PrintLayoutTool.swift
//  vectr
//

import Foundation

enum PrintLayoutTool: String, CaseIterable, Codable {
    case select
    case printBorder
    case registrationMark

    var label: String {
        switch self {
        case .select: return "Select"
        case .printBorder: return "Print Border"
        case .registrationMark: return "Registration Mark"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "arrow.up.and.down.and.arrow.left.and.right"
        case .printBorder: return "rectangle.dashed"
        case .registrationMark: return "plus.viewfinder"
        }
    }
}
