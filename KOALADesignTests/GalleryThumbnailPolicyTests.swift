import Testing
@testable import KOALADesign

@MainActor
struct GalleryThumbnailPolicyTests {
    @Test func quietAutosaveKeepsExistingThumbnail() {
        #expect(
            GalleryThumbnailPolicy.shouldWriteThumbnail(
                refreshRequested: false,
                thumbnailExists: true
            ) == false
        )
    }

    @Test func missingThumbnailIsRewrittenEvenOnAutosave() {
        #expect(
            GalleryThumbnailPolicy.shouldWriteThumbnail(
                refreshRequested: false,
                thumbnailExists: false
            )
        )
    }

    @Test func explicitSaveRewritesThumbnail() {
        #expect(
            GalleryThumbnailPolicy.shouldWriteThumbnail(
                refreshRequested: true,
                thumbnailExists: true
            )
        )
    }
}
