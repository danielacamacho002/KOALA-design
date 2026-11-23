//
//  ViewportNavigationInstaller.swift
//  Koala
//
//  Pinch / two-finger pan / two-finger tap live on a parent of both the UIKit
//  canvas and the SwiftUI overlay. The overlay is a sibling of the canvas, so
//  putting those recognizers only on the canvas lets Move/Scale swallow zoom.
//

import SwiftUI
import UIKit

/// Installs viewport navigation on the nearest ancestor that also hosts the canvas.
struct ViewportNavigationInstaller: UIViewRepresentable {
    var document: KoalaDocument
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
    var document: KoalaDocument?
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
            pinchAnchor = anchorInCanvas(from: gesture, host: view)
        case .changed:
            let anchor = pinchAnchor
            applyViewport(in: view, preserving: anchor) { viewport in
                viewport.zoom(to: pinchStartScale * gesture.scale, anchorViewPoint: anchor)
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

    private func applyViewport(
        in view: UIView,
        preserving anchorViewPoint: CGPoint? = nil,
        mutate: (inout ViewportTransform) -> Void
    ) {
        guard let document else { return }
        var viewport = document.viewport
        mutate(&viewport)
        viewport.clampToCanvasSize(
            in: view.bounds.size,
            canvasSize: zoomExtent(for: document, in: view),
            preserving: anchorViewPoint
        )
        guard viewport != document.viewport else { return }
        document.viewport = viewport
        handle?.noteViewportGestureUpdate()
        handle?.refreshViewport()
    }

    /// Design zoom is limited by the artboard. Print zoom is limited by the page grid,
    /// so pinching out stops once the sheets fit, the same way design mode stops on the canvas.
    private func zoomExtent(for document: KoalaDocument, in host: UIView) -> CGSize {
        guard Self.containsPrintCanvas(host) else { return document.settings.canvasSize }
        let grid = PrintPageGridEngine.gridBounds(for: document.printLayout)
        guard grid.width > 0, grid.height > 0 else { return document.settings.canvasSize }
        return grid.size
    }

    private static func containsPrintCanvas(_ view: UIView) -> Bool {
        if view is PrintLayoutCanvasUIView { return true }
        return view.subviews.contains(where: containsPrintCanvas)
    }

    /// Viewport translation is in canvas coordinates. The recognizer sits on an ancestor,
    /// so the pinch point has to be converted or zoom-out orbits the wrong corner.
    private func anchorInCanvas(from gesture: UIGestureRecognizer, host: UIView) -> CGPoint {
        guard let canvas = Self.canvasView(in: host) else { return gesture.location(in: host) }
        return gesture.location(in: canvas)
    }

    private static func canvasView(in view: UIView) -> UIView? {
        if view is DrawingCanvasUIView || view is PrintLayoutCanvasUIView { return view }
        for subview in view.subviews {
            if let canvas = canvasView(in: subview) { return canvas }
        }
        return nil
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
