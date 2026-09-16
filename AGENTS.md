# Vectr agent notes

Hot files live in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Open that **only** if you do not know where to start. Do not whole-repo scan. Do not read it for a named-file UI tweak.

`refreshCanvas()` is `markDirty()` only, not a canvas redraw. Geometry → `geometryRevision`; print → `printLayoutRevision`; unsaved → `markDirty()` once; undo **before** the change.

New **model / geometry / persistence** behavior gets a Swift Testing test in `vectrTests` (`@MainActor`, not XCTest). Skip UI chrome. If you need the boilerplate, use the `vectr-add-test` skill.

If folders, hot-file paths, revision counters, or listed perf debt changed, update `docs/ARCHITECTURE.md` (keep it short). Use `update-codemap` only if you need that checklist.
