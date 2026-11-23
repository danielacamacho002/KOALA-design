import Testing
import Foundation
@testable import KOALADesign

@MainActor
struct DocumentCodecTests {
    @Test func emptyDocumentRoundTripKeepsNoStrokes() throws {
        let data = try DocumentCodec.encode(KoalaDocument())
        let decoded = try DocumentCodec.decode(data)
        #expect(decoded.strokes.isEmpty)
    }
}
