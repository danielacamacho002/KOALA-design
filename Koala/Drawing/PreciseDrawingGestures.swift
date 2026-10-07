//
//  PreciseDrawingGestures.swift
//  Koala
//
//  Apple Pencil reports a slightly different point from `location(in:)` than the
//  actual nib. Drawing uses `preciseLocation(in:)` so ink lands under the tip.
//  The pan recognizer also keeps the original touch-down sample: UIPanGestureRecognizer
//  only fires `.began` after a few points of movement, which would otherwise start
//  the stroke away from where the Pencil first contacted the glass.
//

import UIKit

enum PreciseTouch {
    static func preferred(in touches: Set<UITouch>) -> UITouch? {
        touches.first(where: { $0.type == .pencil || $0.type == .stylus }) ?? touches.first
    }
}

/// Single-finger / Pencil pan that exposes the digitizer-accurate tip location.
final class PrecisePanGestureRecognizer: UIPanGestureRecognizer {
    /// Latest refined Pencil/finger location in the attached view.
    private(set) var preciseViewPoint: CGPoint?
    /// First sample of this gesture — the actual contact point, before pan hysteresis.
    private(set) var originViewPoint: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches, updateOrigin: true)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches, updateOrigin: false)
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches, updateOrigin: false)
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches, updateOrigin: false)
        super.touchesCancelled(touches, with: event)
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        // The first Pencil sample is often estimated. Refine it before `.began` fires
        // so the stroke origin matches the real tip.
        record(touches, updateOrigin: state == .possible)
        super.touchesEstimatedPropertiesUpdated(touches)
    }

    override func reset() {
        super.reset()
        preciseViewPoint = nil
        originViewPoint = nil
    }

    /// View point to use for this state: origin on `.began`, live tip otherwise.
    func drawingViewPoint(fallbackIn view: UIView) -> CGPoint {
        switch state {
        case .began:
            return originViewPoint ?? location(in: view)
        default:
            return preciseViewPoint ?? location(in: view)
        }
    }

    private func record(_ touches: Set<UITouch>, updateOrigin: Bool) {
        guard let touch = PreciseTouch.preferred(in: touches) else { return }
        let point = touch.preciseLocation(in: view)
        preciseViewPoint = point
        if updateOrigin {
            originViewPoint = point
        }
    }
}

/// Tap that reads the Pencil tip instead of the finger-style hit point.
final class PreciseTapGestureRecognizer: UITapGestureRecognizer {
    private(set) var preciseViewPoint: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches)
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches)
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches)
        super.touchesCancelled(touches, with: event)
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        record(touches)
        super.touchesEstimatedPropertiesUpdated(touches)
    }

    override func reset() {
        super.reset()
        preciseViewPoint = nil
    }

    func drawingViewPoint(fallbackIn view: UIView) -> CGPoint {
        preciseViewPoint ?? location(in: view)
    }

    private func record(_ touches: Set<UITouch>) {
        guard let touch = PreciseTouch.preferred(in: touches) else { return }
        preciseViewPoint = touch.preciseLocation(in: view)
    }
}
