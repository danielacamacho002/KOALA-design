---
name: vectr-add-test
description: Adds Swift Testing unit tests for new Vectr model, geometry, or persistence behavior. Use when implementing a feature, writing tests, or the user mentions Swift Testing, vectrTests, or test coverage.
---

# Add a Vectr unit test

## When to write a test

**Yes:** conversion math, coordinate transforms, codec/snapshot fields, slice/grid engines, join/trim/boolean results.

**Skip:** SwiftUI chrome, icons, copy, layout-only panel tweaks. Say so and stop.

## How

1. Put tests in `vectrTests/`, named `*Tests.swift`.
2. Use Swift Testing, not XCTest:

```swift
import Testing
@testable import vectr

@MainActor
struct ExampleTests {
    @Test func inchesToPoints() {
        #expect(UnitConversion.documentPoints(from: 1, unit: .inches) == 72)
    }
}
```

3. Suites must be `@MainActor` (app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
4. Import `CoreGraphics` / `Foundation` in the test file when comparing numeric or codec values (`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`).
4. Cover the new behavior plus one edge case (empty input, identity transform, round-trip).
5. If `vectrTests` is missing from the Xcode project, add the target first — do not leave orphan files.

## Do not

- Host UI tests or launch the editor for unit logic
- `@testable import` from a second module; there is only `vectr`
- Duplicate existing seed tests in `UnitConversionTests`, `PrintLayoutCoordinateSpaceTests`, `DocumentCodecTests`
