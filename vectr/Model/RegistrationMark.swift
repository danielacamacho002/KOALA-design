//
//  RegistrationMark.swift
//  vectr
//

import CoreGraphics
import Foundation

enum RegistrationMarkKind: String, Codable {
    case crosshair
    case pageNumber
}

struct RegistrationMark: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var position: CGPoint
    var kind: RegistrationMarkKind
    var pageLabel: String?
    var isLocked: Bool = false

    init(
        id: UUID = UUID(),
        position: CGPoint,
        kind: RegistrationMarkKind,
        pageLabel: String? = nil,
        isLocked: Bool = false
    ) {
        self.id = id
        self.position = position
        self.kind = kind
        self.pageLabel = pageLabel
        self.isLocked = isLocked
    }
}
