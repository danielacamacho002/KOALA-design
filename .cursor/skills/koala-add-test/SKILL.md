---
name: koala-add-test
description: Adds a Swift Testing unit test file under KOALADesignTests. Use only when writing a KOALADesignTests file, or when the user asks for a Swift Testing test. Do not use for UI chrome or general feature work.
disable-model-invocation: true
---

# Add a Koala unit test

## When to write a test

**Yes:** conversion math, coordinate transforms, codec/snapshot fields, slice/grid engines, join/trim/boolean results.

**Skip:** SwiftUI chrome, icons, copy, layout-only panel tweaks. Say so and stop.

## How

1. Put tests in `KOALADesignTests/`, named `*Tests.swift`.
2. Use Swift Testing, not XCTest:

```swift
import Testing
@testable import KOALADesign

@MainActor
struct ExampleTests {
    @Test func inchesToPoints() {
        #expect(UnitConversion.documentPoints(from: 1, unit: .inches) == 72)
    }
}
```

3. Suites must be `@MainActor` (app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
4. Import `CoreGraphics` / `Foundation` in the test file when comparing numeric or codec values (`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`).
5. Cover the new behavior plus one edge case (empty input, identity transform, round-trip).
6. If `KOALADesignTests` is missing from the Xcode project, add the target first — do not leave orphan files.

## Do not

- Host UI tests or launch the editor for unit logic
- `@testable import` from a second module; there is only `KOALADesign`
- Duplicate existing seed tests in `UnitConversionTests`, `PrintLayoutCoordinateSpaceTests`, `DocumentCodecTests`
