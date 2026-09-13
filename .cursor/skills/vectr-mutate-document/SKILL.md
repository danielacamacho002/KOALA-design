---
name: vectr-mutate-document
description: Chooses the correct Vectr document update signals (undo, dirty, geometry vs print revision). Use when mutating strokes, layers, selection, undo, auto-save, or when the canvas did not update, refreshCanvas, or markDirty is involved.
---

# Mutate VectrDocument

`refreshCanvas()` **does not redraw the canvas**. It only calls `DocumentStore.markDirty()`.

## Which signal

| Change | Do this |
|--------|---------|
| Geometry users should see on the design canvas | Mutate via `VectrDocument` APIs that already bump `geometryRevision` (or bump it if you added a new mutator) |
| Print layout / print transforms | Bump `printLayoutRevision` (existing print APIs usually do) |
| File should auto-save / show unsaved | `store.markDirty()` once per user action |
| Undoable edit | `pushUndo()` / `recordUndo: true` on the document API — **before** the change |
| Selection / tool / viewport only | Do **not** `pushUndo()`. Viewport pan should not mark dirty unless you intend to persist it |

## Do not

- Call `refreshCanvas()` to force a redraw (it increments `contentRevision` and can schedule auto-save)
- Call `markDirty()` and `refreshCanvas()` for the same action (double dirty)
- `pushUndo()` on every drag tick (`recordUndo: false` during live drag; one undo at gesture end)
- Clone a new `PathSnapEngine` unless the existing one is out of scope

## Persist new fields

If you add stored document state, update **all** of: `currentSnapshot()`, `apply()`, `DocumentCodec.encode`, `EditorView.snapshotFromStore()`.

Read `docs/ARCHITECTURE.md` (revision contract) if unsure. Do not scan the whole repo.
