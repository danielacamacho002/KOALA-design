# vectr

Vectr is an iOS vector drawing app focused on precise shape creation and editing.

## Features

- Draw lines, circles, ellipses, and rectangles
- Edit points, move/scale shapes, and trim geometry
- Apply corner-specific fillets with interactive drag radius control
- Export artwork in multiple formats

## Project Structure

- `vectr/` - app source code
- `vectrTests/` - Swift Testing unit tests
- `vectr.xcodeproj` - Xcode project
- `ExportedTypes.plist` - document type configuration
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - code map (folders, hot files, update rules)

## Getting Started

1. Open `vectr.xcodeproj` in Xcode.
2. Select the `vectr` scheme.
3. Build and run on an iOS simulator or device.

## Tests

Product → Test, or:

```bash
xcodebuild test -scheme vectr -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Use an iPad simulator available on your machine if that name is missing.
