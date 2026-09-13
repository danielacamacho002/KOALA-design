//
//  ProjectRecord.swift
//  vectr
//

import Foundation

nonisolated struct ProjectRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var fileURL: URL
    var thumbnailURL: URL?
    var modifiedAt: Date
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat

    var dimensionsLabel: String {
        "\(Int(canvasWidth)) × \(Int(canvasHeight)) pt"
    }
}
