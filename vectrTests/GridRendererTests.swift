import CoreGraphics
import Testing
@testable import vectr

@MainActor
struct GridRendererTests {
    private var defaultSettings: DocumentSettings { DocumentSettings() }
    private var defaultGrid: GridSettings { GridSettings() }
    private let viewBounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func viewportCenteredOnOrigin(scale: CGFloat) -> ViewportTransform {
        ViewportTransform(
            scale: scale,
            translation: CGPoint(x: viewBounds.midX, y: viewBounds.midY)
        )
    }

    private func liveCache(
        viewport: ViewportTransform,
        settings: DocumentSettings? = nil,
        grid: GridSettings? = nil
    ) -> GridRenderer.PathCache {
        let settings = settings ?? defaultSettings
        let grid = grid ?? defaultGrid
        let paths = GridRenderer.makeLayerPaths(
            viewBounds: viewBounds,
            viewport: viewport,
            grid: grid,
            documentSettings: settings,
            canvasSize: settings.canvasSize,
            padScreens: 1
        )
        return GridRenderer.PathCache(
            coverage: paths.coverage,
            subdiv: grid.visibleSubdivisions(for: settings, scale: viewport.scale),
            major: grid.visualSpacing(for: settings),
            canvasSize: settings.canvasSize
        )
    }

    @Test func emptyCacheNeedsRebuild() {
        let viewport = viewportCenteredOnOrigin(scale: 1)
        #expect(
            GridRenderer.needsPathRebuild(
                cache: nil,
                viewBounds: viewBounds,
                viewport: viewport,
                grid: defaultGrid,
                documentSettings: defaultSettings
            )
        )
    }

    @Test func panInsideDefaultSheetDoesNotNeedRebuild() {
        let start = viewportCenteredOnOrigin(scale: 1)
        let cache = liveCache(viewport: start)
        var panned = start
        panned.translation.x += 120
        panned.translation.y -= 80
        #expect(
            !GridRenderer.needsPathRebuild(
                cache: cache,
                viewBounds: viewBounds,
                viewport: panned,
                grid: defaultGrid,
                documentSettings: defaultSettings
            )
        )
    }

    @Test func zoomWithoutLodChangeDoesNotNeedRebuildOnDefaultSheet() {
        let start = viewportCenteredOnOrigin(scale: 1)
        let cache = liveCache(viewport: start)
        let startSubdiv = defaultGrid.visibleSubdivisions(for: defaultSettings, scale: start.scale)
        var zoomed = start
        zoomed.scale = 1.15
        let zoomedSubdiv = defaultGrid.visibleSubdivisions(for: defaultSettings, scale: zoomed.scale)
        #expect(startSubdiv == zoomedSubdiv)
        #expect(
            !GridRenderer.needsPathRebuild(
                cache: cache,
                viewBounds: viewBounds,
                viewport: zoomed,
                grid: defaultGrid,
                documentSettings: defaultSettings
            )
        )
    }

    @Test func subdivisionChangeNeedsRebuild() {
        let start = viewportCenteredOnOrigin(scale: 1)
        let cache = liveCache(viewport: start)
        var zoomed = start
        zoomed.scale = ViewportTransform.maxScale
        #expect(
            defaultGrid.visibleSubdivisions(for: defaultSettings, scale: start.scale)
                != defaultGrid.visibleSubdivisions(for: defaultSettings, scale: zoomed.scale)
        )
        #expect(
            GridRenderer.needsPathRebuild(
                cache: cache,
                viewBounds: viewBounds,
                viewport: zoomed,
                grid: defaultGrid,
                documentSettings: defaultSettings
            )
        )
    }

    @Test func liveCoverageUsesFullDefaultCanvas() {
        let viewport = viewportCenteredOnOrigin(scale: 1)
        let canvas = GridRenderer.canvasRect(size: defaultSettings.canvasSize)
        let coverage = GridRenderer.coverageRect(
            viewBounds: viewBounds,
            viewport: viewport,
            grid: defaultGrid,
            documentSettings: defaultSettings,
            canvas: canvas,
            padScreens: 1
        )
        #expect(canvas != nil)
        #expect(coverage == canvas!)
    }

    @Test func exportCoverageStaysVisibleOnly() {
        let viewport = viewportCenteredOnOrigin(scale: 4)
        let canvas = GridRenderer.canvasRect(size: defaultSettings.canvasSize)
        let visible = GridRenderer.documentRect(fromViewBounds: viewBounds, viewport: viewport)
        let coverage = GridRenderer.coverageRect(
            viewBounds: viewBounds,
            viewport: viewport,
            grid: defaultGrid,
            documentSettings: defaultSettings,
            canvas: canvas,
            padScreens: 0
        )
        #expect(coverage == visible.intersection(canvas ?? .null))
        #expect(canvas != nil)
        #expect(coverage.width < canvas!.width || coverage.height < canvas!.height)
    }

    @Test func windowedCoverageMissesAfterLargePan() {
        var settings = DocumentSettings()
        settings.canvasWidth = UnitConversion.documentPoints(from: 1_000, unit: .inches)
        settings.canvasHeight = UnitConversion.documentPoints(from: 1_000, unit: .inches)
        let viewport = viewportCenteredOnOrigin(scale: ViewportTransform.maxScale)
        let cache = liveCache(viewport: viewport, settings: settings)
        let canvas = GridRenderer.canvasRect(size: settings.canvasSize)
        #expect(cache.coverage != canvas)

        var panned = viewport
        panned.translation.x += viewBounds.width * 4
        #expect(
            GridRenderer.needsPathRebuild(
                cache: cache,
                viewBounds: viewBounds,
                viewport: panned,
                grid: defaultGrid,
                documentSettings: settings
            )
        )
    }

    @Test func estimatedLineCountIsZeroForEmptyCoverage() {
        #expect(GridRenderer.estimatedLineCount(coverage: .null, minor: 10) == 0)
        #expect(GridRenderer.estimatedLineCount(coverage: .zero, minor: 10) == 0)
        #expect(
            GridRenderer.estimatedLineCount(
                coverage: CGRect(x: 0, y: 0, width: 100, height: 100),
                minor: 0
            ) == 0
        )
    }
}
