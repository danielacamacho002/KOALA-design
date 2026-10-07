//
//  FontCatalog.swift
//  Koala
//

import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// How a built-in font resolves to a concrete platform font.
nonisolated enum FontDesignKind: Equatable, Sendable {
    /// The default system font (San Francisco).
    case systemDefault
    /// The system serif design (New York).
    case systemSerif
    /// A named font resolved by its PostScript name.
    case named(String)
}

nonisolated struct BuiltInFont: Identifiable, Equatable, Sendable {
    var id: String { displayName }
    let displayName: String
    let design: FontDesignKind
}

/// The curated set of built-in fonts. All resolve from iOS system fonts,
/// so no font files are bundled with the app.
nonisolated enum FontCatalog: Sendable {
    static let defaultFontName = "SF Pro"

    static let builtIn: [BuiltInFont] = [
        BuiltInFont(displayName: "SF Pro", design: .systemDefault),
        BuiltInFont(displayName: "Helvetica Neue", design: .named("HelveticaNeue")),
        BuiltInFont(displayName: "Avenir Next", design: .named("AvenirNext-Regular")),
        BuiltInFont(displayName: "Futura", design: .named("Futura-Medium")),
        BuiltInFont(displayName: "New York", design: .systemSerif),
        BuiltInFont(displayName: "Georgia", design: .named("Georgia")),
        BuiltInFont(displayName: "Baskerville", design: .named("Baskerville")),
        BuiltInFont(displayName: "American Typewriter", design: .named("AmericanTypewriter")),
        BuiltInFont(displayName: "Copperplate", design: .named("Copperplate")),
        BuiltInFont(displayName: "Courier New", design: .named("CourierNewPSMT"))
    ]

    static func builtIn(named name: String) -> BuiltInFont? {
        builtIn.first { $0.displayName == name }
    }
}

#if canImport(UIKit)
extension BuiltInFont {
    nonisolated func uiFont(size: CGFloat) -> UIFont {
        switch design {
        case .systemDefault:
            return UIFont.systemFont(ofSize: size)
        case .systemSerif:
            let base = UIFont.systemFont(ofSize: size)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        case .named(let postScriptName):
            return UIFont(name: postScriptName, size: size) ?? UIFont.systemFont(ofSize: size)
        }
    }
}
#endif
