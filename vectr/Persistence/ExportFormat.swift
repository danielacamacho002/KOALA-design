//
//  ExportFormat.swift
//  vectr
//

import Foundation
import UniformTypeIdentifiers

nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case vectr
    case jpeg
    case pdf
    case svg
    case ai

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vectr: return "vectr"
        case .jpeg: return "JPEG"
        case .pdf: return "PDF"
        case .svg: return "SVG"
        case .ai: return "Illustrator (.ai)"
        }
    }

    var fileExtension: String {
        switch self {
        case .vectr: return DocumentCodec.fileExtension
        case .jpeg: return "jpg"
        case .pdf: return "pdf"
        case .svg: return "svg"
        case .ai: return "ai"
        }
    }

    var contentType: UTType {
        switch self {
        case .vectr: return .vectrDocument
        case .jpeg: return .jpeg
        case .pdf: return .pdf
        case .svg: return .svg
        case .ai: return .pdf
        }
    }
}
