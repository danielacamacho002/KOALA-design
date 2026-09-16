---
name: update-codemap
description: Updates docs/ARCHITECTURE.md after an actual folder, hot-file, revision-counter, or listed perf-debt change. Use only then, or when the user asks to update the architecture map. Do not use for ordinary feature or UI work.
disable-model-invocation: true
---

# Update the Vectr code map

## Instructions

1. Read `docs/ARCHITECTURE.md` and `AGENTS.md`.
2. Change only what drifted: folders, hot-file paths, revision contract, canvas rules, add-tool checklist, dated perf debt.
3. Keep the map short (~2 screens). Remove stale paths. Do not paste the map into `AGENTS.md` or rules.
4. If a hot-file path moved, update the short list in `AGENTS.md`.
5. If a listed perf issue was fixed in code, move it from **Perf debt** to a one-line invariant (or delete it).
6. Do not rewrite the whole map for a UI-only tweak.

## Done when

- Paths in the map still compile as real files
- `AGENTS.md` remains a pointer, not a second copy of the map
