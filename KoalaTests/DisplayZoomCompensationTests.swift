import CoreGraphics
import Testing
@testable import Koala

@MainActor
struct DisplayZoomCompensationTests {
    @Test func factorIsOneWhenScalesMatch() {
        #expect(DisplayZoomCompensation.factor(scale: 2, nativeScale: 2, isPad: true) == 1)
    }

    @Test func factorDoesNotShrinkLargerText() {
        // Larger Text raises nativeScale, which already enlarges the UI.
        #expect(DisplayZoomCompensation.factor(scale: 2, nativeScale: 2.2, isPad: true) == 1)
    }

    @Test func factorStaysOneOnIPhoneWhenNativeScaleIsLower() {
        // Plus-class phones render at scale 3 and downsample to nativeScale.
        #expect(DisplayZoomCompensation.factor(scale: 3, nativeScale: 2.608, isPad: false) == 1)
    }

    @Test func factorIgnoresTinyScaleNoise() {
        #expect(DisplayZoomCompensation.factor(scale: 2, nativeScale: 1.995, isPad: true) == 1)
    }

    @Test func factorIsOneForInvalidNativeScale() {
        #expect(DisplayZoomCompensation.factor(scale: 2, nativeScale: 0, isPad: true) == 1)
    }

    @Test func moreSpaceFactorRestoresDefaultPointSize() {
        // 11" panel is 2388px. More Space draws a 2778px framebuffer at @2x.
        let scale: CGFloat = 2
        let nativePixels: CGFloat = 2388
        let moreSpacePoints = 2778 / scale
        let nativeScale = nativePixels / moreSpacePoints
        let factor = DisplayZoomCompensation.factor(scale: scale, nativeScale: nativeScale, isPad: true)
        #expect(factor > 1)
        let layoutPoints = moreSpacePoints / factor
        #expect(abs(layoutPoints - nativePixels / scale) < 0.01)
    }
}
