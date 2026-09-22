# swift-tree Memory

Repo-specific facts. One per line, terse.

## Build, format, release
- `make format-check` / `make format` / `make test` are the only spellings of those commands; CI
  calls the targets. Stock `swift format` defaults (2-space) — no `.swift-format` on purpose.
- Tests: Swift Testing (`import Testing`), hermetic, ~2s. They shell out to the REAL git in temp
  dirs; git on PATH is a test prerequisite.
- Release = bare semver tag (`0.1.0`, no `v`). CI's release job fires on it and only adds notes;
  SwiftPM resolves the tag itself.
- Package targets macOS 14: `Mutex` (Synchronization) is macOS 15 — use `OSAllocatedUnfairLock`.
- A SwiftPM test target with no sources fails the build; add the target with its first test.

## Invariants in the code
- ONE URL spelling everywhere: build with `URL.child(_:)` / `.parent` (no trailing slash).
  URLs are dictionary keys (`listings`, `expanded`, status maps); `deletingLastPathComponent()`
  adds a trailing slash and silently misses every lookup.
- `FileTree.listings` is `@ObservationIgnored` because `children(of:)` fills it lazily while the
  view draws; changes to a loaded listing bump the observed `listingVersion` instead.
- `--no-optional-locks` on every `git status` is load-bearing: without it status rewrites
  `.git/index`, the git-dir watch fires, and the engine refreshes itself forever.
- Repo roots come from walking up by `rev-parse --show-prefix` depth, never `--show-toplevel`
  (resolved `/private/var` spelling). FSEvents paths map back through `resolvedRoot`.
- Nested-repo candidates = untracked AND ignored `dir/` entries holding `.git`, plus
  `.gitmodules` paths (a clean submodule never appears in status).

## Testing seams
- `FileTree(root:options:watcher:lister:git:onError:)` is the internal init: inject
  `FakeWatcher` (per-subscription `emit`), a fake `GitRunner`, or a counting lister.
- `await tree.started?.value` = first full git load done. Later async effects: `eventually { }`.
- Simulate a git command: run it, then `watcher.emit` a path inside the repo's
  `--absolute-git-dir`, which is what FSEvents would report.
