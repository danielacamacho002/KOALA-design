import CoreGraphics
import Foundation
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

    @Test func feetAndMetersToPoints() {
        #expect(UnitConversion.documentPoints(from: 1, unit: .feet) == 864)
        #expect(abs(UnitConversion.documentPoints(from: 1, unit: .meters) - 1000 * 72 / 25.4) < 0.0001)
    }

    @Test func removedUnitsDecodeToNearestRemainingUnit() throws {
        let decoder = JSONDecoder()
        let legacy = try decoder.decode([MeasurementUnit].self, from: Data(#"["points","centimeters","feet"]"#.utf8))
        #expect(legacy == [.inches, .millimeters, .feet])
    }

    @Test func largerUnitsShowMoreDecimals() {
        let oneInch: CGFloat = 72
        #expect(MeasurementUnit.inches.formatted(MeasurementUnit.inches.fromDocumentUnits(oneInch)) == "1.00")
        #expect(MeasurementUnit.millimeters.formatted(MeasurementUnit.millimeters.fromDocumentUnits(oneInch)) == "25.40")
        #expect(MeasurementUnit.feet.formatted(MeasurementUnit.feet.fromDocumentUnits(oneInch)) == "0.083")
        #expect(MeasurementUnit.meters.formatted(MeasurementUnit.meters.fromDocumentUnits(oneInch)) == "0.0254")
    }

    @Test func canvasMaximumIsSameLengthInEveryUnit() {
        let reference = DocumentSettings.maximumCanvasExtent(for: .inches)
        for unit in MeasurementUnit.allCases {
            #expect(abs(DocumentSettings.maximumCanvasExtent(for: unit) - reference) < 0.001)
        }
    }
}
