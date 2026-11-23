//
//  PathExtruder.swift
//  Koala
//

import SceneKit
import UIKit

enum PathExtruder {
    static func canExtrude(_ stroke: VectorStroke) -> Bool {
        stroke.isClosed && stroke.points.count >= 3
    }

    static func makeShape(from stroke: VectorStroke, depth: CGFloat) -> SCNShape? {
        guard canExtrude(stroke) else { return nil }
        #if canImport(UIKit)
        let path = UIBezierPath(cgPath: stroke.displayPath())
        let shape = SCNShape(path: path, extrusionDepth: max(depth, 0.1))
        shape.firstMaterial?.diffuse.contents = stroke.strokeColor.uiColor
        shape.firstMaterial?.isDoubleSided = true
        return shape
        #else
        return nil
        #endif
    }

    static func makeNode(from stroke: VectorStroke, depth: CGFloat) -> SCNNode? {
        guard let shape = makeShape(from: stroke, depth: depth) else { return nil }
        let node = SCNNode(geometry: shape)
        node.eulerAngles.x = -.pi / 2
        return node
    }
}

#if canImport(UIKit)
private extension CodableColor {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif
