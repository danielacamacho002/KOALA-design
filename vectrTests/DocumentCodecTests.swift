import Testing
import Foundation
@testable import vectr

@MainActor
struct DocumentCodecTests {
    @Test func emptyDocumentRoundTripKeepsNoStrokes() throws {
        let data = try DocumentCodec.encode(VectrDocument())
        let decoded = try DocumentCodec.decode(data)
        #expect(decoded.strokes.isEmpty)
    }
}
