# Vectr agent notes

Before exploring the repo, read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Start from the hot files listed there. Do not whole-repo scan for feature work.

## After structural changes

If folders, hot files, revision counters, or perf debt changed, use the `update-codemap` skill and keep the map short.

## Tests

New **model / geometry / persistence** behavior gets a Swift Testing test in `vectrTests`. UI chrome (layout, icons, copy) can skip. Use the `vectr-add-test` skill.

## Document mutations

`refreshCanvas()` is **not** a canvas redraw — it only marks the file dirty. See the architecture revision contract, or the `vectr-mutate-document` skill.
