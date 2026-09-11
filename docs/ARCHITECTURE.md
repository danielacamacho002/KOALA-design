# Vectr architecture

iPad vector editor: design on a canvas, then arrange artwork for tiled print. iPhone is a placeholder. Source lives in `vectr/` (~120 Swift files).

## Folders

| Folder | Role |
|--------|------|
| `Model/` | Document, tools, viewport, undo snapshots |
| `Drawing/` | UIKit design canvas, gestures, snap/join/trim/boolean |
| `Rendering/` | Stroke/grid/text drawing, thumbnails, print canvas UIView |
| `Persistence/` | `.vectr` codec, project library, import/export |
| `UI/` | SwiftUI chrome, overlays, tool panels, print-layout screens |
| `Commands/` | In-progress shape/polyline command sessions (not persisted) |
| `PrintLayout/` | Print slice/grid/coordinate math |
| `Extrusion/` | Experimental 3D preview — skip unless the task is extrusion |

## Main flow

`vectrApp` → `ContentView` → iPad `ProjectGalleryView` → `EditorView` (`DocumentStore` + `VectrDocument`).

- **Design:** `DrawingCanvasView` → `DrawingCanvasUIView` (CAShapeLayer strokes + CG grid)
- **Print:** `PrintLayoutView` → `PrintLayoutCanvasView` → `PrintLayoutCanvasUIView`
- **Save/export:** `DocumentCodec` / `ExportRouter` (PDF, tiled PDF, SVG, JPEG)

## Open these first

- `vectr/Model/VectrDocument.swift` — source of truth
- `vectr/Persistence/DocumentStore.swift` — file, dirty, `contentRevision`
- `vectr/UI/EditorView.swift` — editor orchestration
- `vectr/Drawing/DrawingCanvasView.swift` + `DrawingCanvasUIView.swift`
- `vectr/UI/PrintLayout/PrintLayoutCanvasView.swift` + `Rendering/PrintLayout/PrintLayoutCanvasUIView.swift`
- `vectr/Persistence/DocumentCodec.swift`

Do not start in `ShapeGeometry`, `PathJoinEngine`, `TrimEngine`, or `PolygonBoolean` unless the task is that geometry.

## Revision contract

These counters mean different things. Mixing them is the usual bug.

| Signal | Meaning |
|--------|---------|
| `geometryRevision` | Design canvas should reload stroke/text layers |
| `printLayoutRevision` | Print layout structure/transforms changed |
| `undoRevision` | Undo/redo stack changed (undo UI) |
| `DocumentStore.contentRevision` / `markDirty()` | File is unsaved; SwiftUI + auto-save. **Not** a canvas redraw |
| `EditorView.refreshCanvas()` | **Only** `markDirty()`. Does not refresh the UIKit canvas |

`pushUndo()` copies a full `DocumentSnapshot` (including `referenceImageData`). New persisted fields must be added in `currentSnapshot()`, `apply()`, `DocumentCodec.encode`, and `EditorView.snapshotFromStore()`.

## Canvas updates

**Design** (`DrawingCanvasView.Coordinator`): diff viewport vs geometry vs selection vs command preview. Pan/zoom should transform existing layers, not rebuild every stroke.

**Print** (`PrintLayoutCanvasView.updateUIView`): today calls `reloadAll()` on almost every SwiftUI update; `printLayoutRevision` / `geometryRevision` are passed in and ignored. Match design-canvas diffing when touching this path.

## Adding a tool

1. `Model/DrawingTool.swift` (`ToolCategory`) or `Model/PrintLayoutTool.swift`
2. Palette: `UI/SideToolPaletteView.swift` or print toolbar
3. Wire actions in `UI/EditorView.swift` (or `PrintLayoutView.swift`)
4. Panel chrome via `UI/ToolPanelStyle.swift`
5. Optional: `Commands/` session and/or overlay in `CanvasOverlayView` / `PrintLayoutOverlayView`

Print-layout features often need a **second** panel/canvas path. Do not assume design-mode UI appears in print mode.

## Perf debt (2026-09)

- Export, save, thumbnails, and project load run on the main thread
- Undo snapshots can duplicate `referenceImageData` up to 50×
- Font registration in `vectrApp.init` is sync disk + Core Text
- `refreshCanvas()` over-marks dirty (including recenter animation steps)
- Layer thumbnails regenerate on every `geometryRevision` (including live drag)
- Pretty-printed JSON on every save
