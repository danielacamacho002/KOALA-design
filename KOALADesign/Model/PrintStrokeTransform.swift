//
//  PrintStrokeTransform.swift
//  Koala
//

import CoreGraphics
import Foundation

nonisolated struct PrintStrokeTransform: Codable, Equatable, Sendable {
    var translation: CGPoint = .zero
    var rotation: CGFloat = 0
    var flipHorizontal: Bool = false
    var flipVertical: Bool = false

    static let identity = PrintStrokeTransform()
}
