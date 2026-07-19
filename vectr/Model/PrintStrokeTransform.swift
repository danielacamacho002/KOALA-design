//
//  PrintStrokeTransform.swift
//  vectr
//

import CoreGraphics
import Foundation

struct PrintStrokeTransform: Codable, Equatable {
    var translation: CGPoint = .zero
    var rotation: CGFloat = 0
    var flipHorizontal: Bool = false
    var flipVertical: Bool = false

    static let identity = PrintStrokeTransform()
}
