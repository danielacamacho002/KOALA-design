//
//  ViewportNavigationInstaller.swift
//  vectr
//
//  Pinch / two-finger pan / two-finger tap live on a parent of both the UIKit
//  canvas and the SwiftUI overlay. The overlay is a sibling of the canvas, so
//  putting those recognizers only on the canvas lets Move/Scale swallow zoom.
//

import SwiftUI
import UIKit

/// Installs viewport navigation on the nearest ancestor that also hosts the canvas.
struct ViewportNavigationInstaller: UIViewRepresentable {
    var document: VectrDocument
    var viewportHandle: CanvasViewportHandle
    var onTwoFingerTap: (() -> Void)?

    func makeCoordinator() -> ViewportNavigationSession {
        ViewportNavigationSession()
    }

    func makeUIView(context: Context) -> ViewportNavigationProbeView {
        let probe = ViewportNavigationProbeView()
        probe.session = context.coordinator
        configure(context.coordinator)
        return probe
    }

    func updateUIView(_ uiView: ViewportNavigationProbeView, context: Context) {
        uiView.session = context.coordinator
        configure(context.coordinator)
        context.coordinator.install(from: uiView)
    }

    private func configure(_ session: ViewportNavigationSession) {
        session.document = document
        session.handle = viewportHandle
        session.onTwoFingerTap = onTwoFingerTap
    }
}

final class ViewportNavigationProbeView: UIView {
    weak var session: ViewportNavigationSession?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        session?.install(from: self)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        session?.install(from: self)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            session?.uninstall()
        }
    }
}

@MainActor
final class ViewportNavigationSession: NSObject, UIGestureRecognizerDelegate {
    var document: VectrDocument?
    var handle: CanvasViewportHandle?
    var onTwoFingerTap: (() -> Void)?

    private let pinch = UIPinchGestureRecognizer()
    private let twoFingerPan = UIPanGestureRecognizer()
    private let twoFingerTap = UITapGestureRecognizer()
    private var pinchStartScale: CGFloat = 1
    private var pinchAnchor: CGPoint = .zero
    private weak var installedOn: UIView?

    override init() {
        super.init()
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        pinch.cancelsTouchesInView = false

        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.addTarget(self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.delegate = self
        twoFingerPan.cancelsTouchesInView = false

        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.addTarget(self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.delegate = self
        twoFingerTap.cancelsTouchesInView = false
        twoFingerTap.require(toFail: pinch)
        twoFingerTap.require(toFail: twoFingerPan)
    }

    func install(from probe: UIView) {
        guard let host = Self.hostView(containingCanvasNear: probe) else { return }
        guard installedOn !== host else { return }
        uninstall()
        installedOn = host
        host.isMultipleTouchEnabled = true
        host.addGestureRecognizer(pinch)
        host.addGestureRecognizer(twoFingerPan)
        host.addGestureRecognizer(twoFingerTap)
    }

    func uninstall() {
        pinch.view?.removeGestureRecognizer(pinch)
        twoFingerPan.view?.removeGestureRecognizer(twoFingerPan)
        twoFingerTap.view?.removeGestureRecognizer(twoFingerTap)
        installedOn = nil
    }

    private static func hostView(containingCanvasNear probe: UIView) -> UIView? {
        var current = probe.superview
        while let view = current {
            if containsCanvas(view) {
                return view
            }
            current = view.superview
        }
        return probe.superview
    }

    private static func containsCanvas(_ view: UIView) -> Bool {
        if view is DrawingCanvasUIView || view is PrintLayoutCanvasUIView {
            return true
        }
        return view.subviews.contains(where: containsCanvas)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let view = gesture.view, let document else { return }
        switch gesture.state {
        case .began:
            cancelCompetingRecognizers()
            handle?.cancelViewportAnimation()
            pinchStartScale = document.viewport.scale
            pinchAnchor = gesture.location(in: view)
        case .changed:
            applyViewport(in: view) { viewport in
                viewport.zoom(to: pinchStartScale * gesture.scale, anchorViewPoint: pinchAnchor)
            }
        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        switch gesture.state {
        case .began:
            cancelCompetingRecognizers()
            handle?.cancelViewportAnimation()
        case .changed:
            let translation = gesture.translation(in: view)
            applyViewport(in: view) { viewport in
                viewport.translation.x += translation.x
                viewport.translation.y += translation.y
            }
            gesture.setTranslation(.zero, in: view)
        default:
            break
        }
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onTwoFingerTap?()
    }

    private func applyViewport(in view: UIView, mutate: (inout ViewportTransform) -> Void) {
        guard let document else { return }
        var viewport = document.viewport
        mutate(&viewport)
        viewport.clampToCanvasSize(
            in: view.bounds.size,
            canvasSize: document.settings.canvasSize
        )
        guard viewport != document.viewport else { return }
        document.viewport = viewport
        handle?.noteViewportGestureUpdate()
        handle?.refreshViewport()
    }

    /// SwiftUI overlay drags are 1-finger pans that do not fail when a second
    /// finger lands, which is what blocks pinch on some iPads. Kill them once
    /// viewport navigation has begun.
    private func cancelCompetingRecognizers() {
        guard let root = installedOn else { return }
        cancelRecognizers(in: root)
    }

    private func cancelRecognizers(in view: UIView) {
        for recognizer in view.gestureRecognizers ?? [] {
            if recognizer === pinch || recognizer === twoFingerPan || recognizer === twoFingerTap {
                continue
            }
            if recognizer is UIPanGestureRecognizer || recognizer is UIPinchGestureRecognizer {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
        }
        for subview in view.subviews {
            cancelRecognizers(in: subview)
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
