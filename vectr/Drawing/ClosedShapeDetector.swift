//
//  ClosedShapeDetector.swift
//  vectr
//

import CoreGraphics
import Foundation

enum ClosedShapeDetector {
    static func reconcile(document: VectrDocument) {
        let tolerance = document.grid.spacing * 0.5

        for index in document.strokes.indices {
            guard !document.strokes[index].isClosed,
                  !document.strokes[index].isConstruction,
                  document.strokes[index].points.count >= 3,
                  let first = document.strokes[index].points.first,
                  let last = document.strokes[index].points.last else { continue }

            if hypot(first.x - last.x, first.y - last.y) <= tolerance {
                document.strokes[index].isClosed = true
            }
        }
    }
}
