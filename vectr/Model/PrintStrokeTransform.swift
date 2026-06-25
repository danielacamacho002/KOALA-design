//
//  PrintStrokeTransform.swift
//  vectr
//

import CoreGraphics
import Foundation

struct PrintStrokeTransform: Codable, Equatable {
    var translation: CGPoint = .zero
    var rotation: CGFloat = 0

    static let identity = PrintStrokeTransform()
}
