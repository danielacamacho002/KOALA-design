import CoreGraphics
import Testing
@testable import Koala

@MainActor
struct UnitConversionTests {
    @Test func inchesToPoints() {
        #expect(UnitConversion.documentPoints(from: 1, unit: .inches) == 72)
    }

    @Test func pointsToInches() {
        #expect(UnitConversion.displayValue(from: 72, unit: .inches) == 1)
    }
}
