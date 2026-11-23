//
//  DisplayZoomCompensation.swift
//  Koala
//
//  iPad Display Zoom "More Space" packs more points onto the same screen, so
//  every fixed-point control gets physically smaller. Lay the window out at the
//  Default point size and scale it back up. Larger Text (nativeScale above
//  scale) and non-iPad devices are left alone.
//

import ObjectiveC
import SwiftUI
import UIKit

enum DisplayZoomCompensation {
    /// 1 at Default and Larger Text. Greater than 1 only for iPad More Space.
    static func factor(scale: CGFloat, nativeScale: CGFloat, isPad: Bool) -> CGFloat {
        guard isPad, nativeScale > 0.01 else { return 1 }
        let raw = scale / nativeScale
        // Ignore float noise. More Space is well above this.
        return raw > 1.01 ? raw : 1
    }

    static var liveFactor: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let screen = scene?.screen ?? .main
        let isPad = (scene?.traitCollection.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom) == .pad
        return factor(scale: screen.scale, nativeScale: screen.nativeScale, isPad: isPad)
    }

    /// Pixels per layout point. Matches `UIScreen.scale` at Default. More Space
    /// multiplies by the compensation factor so a shrunken layout still fills
    /// the window's backing store.
    static var layerContentsScale: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let screen = scene?.screen ?? .main
        return screen.scale * liveFactor
    }

    /// Observes new windows when More Space is on. Default zoom does not register.
    static func startIfNeeded() {
        guard liveFactor > 1.01, !observingWindows else { return }
        observingWindows = true
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? UIWindow else { return }
            DisplayZoomWindow.install(on: window)
        }
    }

    private static var observingWindows = false

    fileprivate static func factor(for window: UIWindow) -> CGFloat {
        let screen = window.windowScene?.screen ?? .main
        let isPad = window.traitCollection.userInterfaceIdiom == .pad
            || UIDevice.current.userInterfaceIdiom == .pad
        return factor(scale: screen.scale, nativeScale: screen.nativeScale, isPad: isPad)
    }
}

/// Hidden hook so the key window is compensated even if it appeared before
/// the visibility observer. Inserted only when More Space is active.
struct DisplayZoomInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> DisplayZoomInstallerView {
        DisplayZoomInstallerView()
    }

    func updateUIView(_ uiView: DisplayZoomInstallerView, context: Context) {
        uiView.installIfNeeded()
    }
}

final class DisplayZoomInstallerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        DisplayZoomCompensation.startIfNeeded()
        guard let window else { return }
        DisplayZoomWindow.install(on: window)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}

/// Window whose bounds are the Default point size while its transform fills
/// the More Space frame. No stored properties: the instance may be an existing
/// `UIWindow` whose class was swapped.
final class DisplayZoomWindow: UIWindow {
    private static var applyingKey: UInt8 = 0
    private static var passesKey: UInt8 = 0

    static func install(on window: UIWindow) {
        let factor = DisplayZoomCompensation.factor(for: window)
        guard factor > 1.01 else { return }
        if isSystemChrome(window) { return }

        let current: AnyClass? = object_getClass(window)
        if current === DisplayZoomWindow.self {
            return
        }
        if current === UIWindow.self {
            object_setClass(window, DisplayZoomWindow.self)
            let frame = window.frame
            window.frame = frame
            applyRenderScale(on: window, factor: factor)
            return
        }
        guard window.isKeyWindow else { return }
        DisplayZoomRootCompensation.install(on: window, factor: factor)
        applyRenderScale(on: window, factor: factor)
    }

    override var frame: CGRect {
        get { super.frame }
        set { apply(visualFrame: newValue) }
    }

    private func apply(visualFrame: CGRect) {
        if isApplying {
            super.frame = visualFrame
            return
        }
        let factor = DisplayZoomCompensation.factor(for: self)
        guard factor > 1.01, visualFrame.width > 1, visualFrame.height > 1 else {
            if transform != .identity {
                super.transform = .identity
            }
            super.frame = visualFrame
            return
        }

        let layoutSize = CGSize(width: visualFrame.width / factor, height: visualFrame.height / factor)
        let visualCenter = CGPoint(x: visualFrame.midX, y: visualFrame.midY)
        if abs(transform.a - factor) < 0.001,
           abs(bounds.width - layoutSize.width) < 0.5,
           abs(bounds.height - layoutSize.height) < 0.5,
           abs(center.x - visualCenter.x) < 0.5,
           abs(center.y - visualCenter.y) < 0.5 {
            return
        }
        // A system layout that keeps resetting the frame must not spin forever.
        guard layoutPasses < 6 else { return }
        layoutPasses += 1
        DispatchQueue.main.async { [weak self] in
            self?.layoutPasses = 0
        }

        isApplying = true
        super.transform = .identity
        super.frame = CGRect(origin: .zero, size: layoutSize)
        super.center = visualCenter
        super.transform = CGAffineTransform(scaleX: factor, y: factor)
        isApplying = false
    }

    private static func isSystemChrome(_ window: UIWindow) -> Bool {
        let name = NSStringFromClass(type(of: window))
        return name.contains("TextEffects")
            || name.contains("Keyboard")
            || name.contains("RemoteKeyboard")
    }

    private static func applyRenderScale(on window: UIWindow, factor: CGFloat) {
        guard let scene = window.windowScene else { return }
        // Reading displayScale before an override exists throws.
        scene.traitOverrides.displayScale = scene.screen.scale * factor
    }

    private var isApplying: Bool {
        get { (objc_getAssociatedObject(self, &Self.applyingKey) as? NSNumber)?.boolValue ?? false }
        set {
            objc_setAssociatedObject(
                self,
                &Self.applyingKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private var layoutPasses: Int {
        get { (objc_getAssociatedObject(self, &Self.passesKey) as? NSNumber)?.intValue ?? 0 }
        set {
            objc_setAssociatedObject(
                self,
                &Self.passesKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

/// Used when the app window is a private subclass and its class cannot be swapped.
/// Scales each sibling of this monitor, which covers the root view and sheets
/// hosted in the same window.
enum DisplayZoomRootCompensation {
    static func install(on window: UIWindow, factor: CGFloat) {
        guard factor > 1.01 else { return }
        if window.subviews.contains(where: { $0 is DisplayZoomRootMonitor }) { return }
        let monitor = DisplayZoomRootMonitor()
        monitor.isUserInteractionEnabled = false
        monitor.backgroundColor = .clear
        monitor.frame = window.bounds
        monitor.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.insertSubview(monitor, at: 0)
    }
}

private final class DisplayZoomRootMonitor: UIView {
    private var applying = false
    private var passes = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !applying, let window else { return }
        let factor = DisplayZoomCompensation.liveFactor
        guard passes < 6 else { return }
        applying = true
        defer { applying = false }
        var changed = false
        for subview in window.subviews where subview !== self {
            if DisplayZoomLayout.apply(to: subview, factor: factor) {
                changed = true
            }
        }
        guard changed else { return }
        passes += 1
        DispatchQueue.main.async { [weak self] in
            self?.passes = 0
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}

private enum DisplayZoomLayout {
    /// Scales `view` around its current center so its visual size stays put
    /// while layout uses Default points. Returns true when it changed geometry.
    @discardableResult
    static func apply(to view: UIView, factor: CGFloat) -> Bool {
        guard factor > 1.01, view.bounds.width > 1, view.bounds.height > 1 else { return false }
        let visualSize: CGSize
        let visualCenter = view.center
        if abs(view.transform.a - factor) < 0.001 {
            visualSize = CGSize(width: view.bounds.width * factor, height: view.bounds.height * factor)
        } else {
            visualSize = view.bounds.size
        }
        let layout = CGSize(width: visualSize.width / factor, height: visualSize.height / factor)
        if abs(view.bounds.width - layout.width) < 0.5,
           abs(view.bounds.height - layout.height) < 0.5,
           abs(view.transform.a - factor) < 0.001 {
            return false
        }
        view.transform = .identity
        view.bounds = CGRect(origin: .zero, size: layout)
        view.center = visualCenter
        view.transform = CGAffineTransform(scaleX: factor, y: factor)
        return true
    }
}
