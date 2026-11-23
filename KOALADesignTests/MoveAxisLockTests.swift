import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct MoveAxisLockTests {
    @Test func staysFreeUntilThreshold() {
        let short = MoveAxisLock.resolvedAxis(
            current: .free,
            viewTranslation: CGSize(width: 6, height: 2),
            enabled: true
        )
        #expect(short == .free)

        let onThreshold = MoveAxisLock.resolvedAxis(
            current: .free,
            viewTranslation: CGSize(width: MoveAxisLock.thresholdPoints, height: 0),
            enabled: true
        )
        #expect(onThreshold == .free)
    }

    @Test func dominantAxisAfterThreshold() {
        let horizontal = MoveAxisLock.resolvedAxis(
            current: .free,
            viewTranslation: CGSize(width: 40, height: 10),
            enabled: true
        )
        #expect(horizontal == .horizontal)

        let vertical = MoveAxisLock.resolvedAxis(
            current: .free,
            viewTranslation: CGSize(width: 10, height: 40),
            enabled: true
        )
        #expect(vertical == .vertical)
    }

    @Test func stickyAxisIgnoresLaterDirectionChange() {
        let locked = MoveAxisLock.resolvedAxis(
            current: .horizontal,
            viewTranslation: CGSize(width: 5, height: 80),
            enabled: true
        )
        #expect(locked == .horizontal)
    }

    @Test func disabledAlwaysFree() {
        let axis = MoveAxisLock.resolvedAxis(
            current: .free,
            viewTranslation: CGSize(width: 100, height: 0),
            enabled: false
        )
        #expect(axis == .free)
    }

    @Test func constrainedDeltaZerosOffAxis() {
        let delta = CGPoint(x: 12, y: -7)
        #expect(MoveAxisLock.constrainedDelta(delta, axis: .free) == delta)
        #expect(MoveAxisLock.constrainedDelta(delta, axis: .horizontal) == CGPoint(x: 12, y: 0))
        #expect(MoveAxisLock.constrainedDelta(delta, axis: .vertical) == CGPoint(x: 0, y: -7))
    }

    @Test func exactDiagonalTiePrefersVertical() {
        let axis = MoveAxisLock.resolvedAxis(
            current: .free,
            viewTranslation: CGSize(width: 20, height: -20),
            enabled: true
        )
        #expect(axis == .vertical)
    }
}
