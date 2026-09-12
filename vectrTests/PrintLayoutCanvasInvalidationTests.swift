import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct PrintLayoutCanvasInvalidationTests {
    @Test func unchangedInputsAfterSeedProduceNoFlags() {
        var invalidation = seededInvalidation()
        let change = consume(invalidation: &invalidation)

        #expect(!change.geometryChanged)
        #expect(!change.selectionChanged)
        #expect(!change.viewportChanged)
        #expect(!change.viewportAlreadyHandled)
        #expect(!change.printLayoutChanged)
        #expect(!change.sheetGridChanged)
        #expect(!change.overlaySettingsChanged)
        #expect(!change.artworkLayoutChanged)
        #expect(!change.selectedArtworkOnly)
    }

    @Test func viewportOnlySetsViewportFlag() {
        var invalidation = seededInvalidation()
        var viewport = ViewportTransform()
        viewport.translation = CGPoint(x: 12, y: 40)
        let change = consume(invalidation: &invalidation, viewport: viewport)

        #expect(change.viewportChanged)
        #expect(!change.viewportAlreadyHandled)
        #expect(!change.geometryChanged)
        #expect(!change.selectionChanged)
        #expect(!change.printLayoutChanged)
        #expect(!change.artworkLayoutChanged)
    }

    @Test func canvasHandledViewportSuppressesSecondRefresh() {
        var invalidation = seededInvalidation()
        invalidation.markViewportHandledByCanvas()

        var viewport = ViewportTransform()
        viewport.scale = 2
        let change = consume(invalidation: &invalidation, viewport: viewport)

        #expect(change.viewportChanged)
        #expect(change.viewportAlreadyHandled)
    }

    @Test func handledFlagSurvivesNonViewportUpdates() {
        let selected = UUID()
        var invalidation = seededInvalidation()
        invalidation.markViewportHandledByCanvas()

        let selectionChange = consume(invalidation: &invalidation, selectedStrokeID: selected)
        #expect(selectionChange.selectionChanged)
        #expect(!selectionChange.viewportChanged)
        #expect(!selectionChange.viewportAlreadyHandled)

        var viewport = ViewportTransform()
        viewport.translation = CGPoint(x: 8, y: 0)
        let viewportChange = consume(
            invalidation: &invalidation,
            selectedStrokeID: selected,
            viewport: viewport
        )
        #expect(viewportChange.viewportChanged)
        #expect(viewportChange.viewportAlreadyHandled)
    }

    @Test func selectionOnlySetsSelectionFlag() {
        var invalidation = seededInvalidation()
        let change = consume(invalidation: &invalidation, selectedStrokeID: UUID())

        #expect(change.selectionChanged)
        #expect(!change.geometryChanged)
        #expect(!change.viewportChanged)
        #expect(!change.printLayoutChanged)
        #expect(!change.artworkLayoutChanged)
    }

    @Test func geometryRevisionSetsGeometryFlag() {
        var invalidation = seededInvalidation()
        let change = consume(invalidation: &invalidation, geometryRevision: 4)

        #expect(change.geometryChanged)
        #expect(!change.selectionChanged)
        #expect(!change.printLayoutChanged)
        #expect(!change.viewportChanged)
    }

    @Test func paperGridChangeSetsSheetGridNotArtwork() {
        var invalidation = seededInvalidation()
        var settings = PrintLayoutSettings()
        settings.columns = 5
        let change = consume(
            invalidation: &invalidation,
            printLayoutRevision: 1,
            printLayout: settings
        )

        #expect(change.printLayoutChanged)
        #expect(change.sheetGridChanged)
        #expect(!change.overlaySettingsChanged)
        #expect(!change.artworkLayoutChanged)
        #expect(!change.selectedArtworkOnly)
        #expect(!change.geometryChanged)
    }

    @Test func cutToolChangeSetsOverlayNotSheets() {
        var invalidation = seededInvalidation()
        var settings = PrintLayoutSettings()
        settings.activeTool = .cut
        let change = consume(
            invalidation: &invalidation,
            printLayoutRevision: 1,
            printLayout: settings
        )

        #expect(change.printLayoutChanged)
        #expect(change.overlaySettingsChanged)
        #expect(!change.sheetGridChanged)
        #expect(!change.artworkLayoutChanged)
    }

    @Test func selectedTransformIsArtworkOnly() {
        let selectedID = UUID()
        var invalidation = PrintLayoutCanvasInvalidation()
        _ = consume(
            invalidation: &invalidation,
            selectedStrokeID: selectedID,
            didSwapDocument: true
        )
        let change = consume(
            invalidation: &invalidation,
            printLayoutRevision: 1,
            selectedStrokeID: selectedID
        )

        #expect(change.printLayoutChanged)
        #expect(change.artworkLayoutChanged)
        #expect(change.selectedArtworkOnly)
        #expect(!change.sheetGridChanged)
        #expect(!change.overlaySettingsChanged)
        #expect(!change.geometryChanged)
        #expect(!change.selectionChanged)
    }

    @Test func contentOffsetUpdatesAllArtwork() {
        let selectedID = UUID()
        var invalidation = PrintLayoutCanvasInvalidation()
        _ = consume(
            invalidation: &invalidation,
            selectedStrokeID: selectedID,
            didSwapDocument: true
        )
        var settings = PrintLayoutSettings()
        settings.contentOffset = CGPoint(x: 40, y: -12)
        let change = consume(
            invalidation: &invalidation,
            printLayoutRevision: 1,
            printLayout: settings,
            selectedStrokeID: selectedID
        )

        #expect(change.artworkLayoutChanged)
        #expect(!change.selectedArtworkOnly)
        #expect(!change.sheetGridChanged)
    }

    @Test func clearPrintSelectionDoesNotBumpPrintLayoutRevision() {
        let document = VectrDocument()
        document.printSelectedStrokeID = UUID()
        let revision = document.printLayoutRevision
        document.clearPrintSelection()
        #expect(document.printSelectedStrokeID == nil)
        #expect(document.printSelectedTextID == nil)
        #expect(document.printLayoutRevision == revision)
    }
}

@MainActor
private func seededInvalidation() -> PrintLayoutCanvasInvalidation {
    var invalidation = PrintLayoutCanvasInvalidation()
    _ = consume(invalidation: &invalidation, didSwapDocument: true)
    return invalidation
}

@MainActor
private func consume(
    invalidation: inout PrintLayoutCanvasInvalidation,
    geometryRevision: Int = 0,
    printLayoutRevision: Int = 0,
    printLayout: PrintLayoutSettings = PrintLayoutSettings(),
    selectedStrokeID: UUID? = nil,
    selectedTextID: UUID? = nil,
    viewport: ViewportTransform = ViewportTransform(),
    didSwapDocument: Bool = false
) -> PrintLayoutCanvasInvalidation.Change {
    invalidation.consume(
        geometryRevision: geometryRevision,
        printLayoutRevision: printLayoutRevision,
        printLayout: printLayout,
        selectedStrokeID: selectedStrokeID,
        selectedTextID: selectedTextID,
        viewport: viewport,
        didSwapDocument: didSwapDocument
    )
}
