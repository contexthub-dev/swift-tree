# swift-tree Memory

Repo-specific facts. One per line, terse.

## Build, format, release
- `make format-check` / `make format` / `make test` are the only spellings of those commands; CI
  calls the targets. Stock `swift format` defaults (2-space) — no `.swift-format` on purpose.
- Tests: Swift Testing (`import Testing`), hermetic, ~2s. They shell out to the REAL git in temp
  dirs; git on PATH is a test prerequisite.
- Release = bare semver tag (`0.2.0`, no `v`), cut ONLY by `release.yml` (Actions → Release → run
  with `version`). It commits the devicon font on a detached release commit on top of main and pushes
  just the tag. Never push a tag by hand: it would ship without the font. `ci.yml` has no tag trigger.
- `make fonts` fetches the latest devicon (TTF, license, map from its CSS) into
  `Sources/SwiftTree/Resources/DevIcons/`. Gitignored except README.md, which must stay committed:
  SwiftPM fails the build if a declared `.copy` resource folder is missing.
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
- A replaced `FileTree` isn't freed at once: `register`'s first-snapshot Task holds it ~0.2s.
  Tests that assert release must poll.
- `register` with `detectGit = false` does NOT throw (the README says it does); it just never
  calls back. Only `snapshot` throws `gitDetectionDisabled`.

- DevIcons: public `FileTree` init passes `DevIcons.shared` (when `useDevIcons`); the internal init
  defaults `devIcons: nil`, so every existing test is hermetic with or without the font. The one
  real-font test is `.enabled(if:)` the bundled TTF exists (skipped locally until `make fonts`).
- devicon's minified CSS holds glyphs as LITERAL private-use chars (not `\e…`) and groups selectors
  (`.a:before,.b:before{…}`): v2.17.0 = 1,491 names. `less` and `toml` have no icon. Table entries
  were checked against the map; re-check when adding one.
- `swift scripts/x.swift` (script mode) rejects bare `/regex/` literals; use `#/…/#`.

## Testing seams
- `FileTree(root:options:watcher:lister:git:onError:)` is the internal init: inject
  `FakeWatcher` (per-subscription `emit`), a fake `GitRunner`, or a counting lister.
- `await tree.started?.value` = first full git load done. Later async effects: `eventually { }`.
- Simulate a git command: run it, then `watcher.emit` a path inside the repo's
  `--absolute-git-dir`, which is what FSEvents would report.

## Demo app
- `demo/` is its own SwiftPM package (path dep `..`), so consumers never resolve it. `make demo`
  = build + launch (`ROOT=<folder>` optional); `make demo-test` = build + test, the CI gate.
  Never point CI at `make demo`: it opens a window and never exits. Format paths list `demo/Package.swift demo/Sources demo/Tests`, never plain
  `demo` (that would lint `demo/.build`).
- `swift run --package-path demo SwiftTreeDemo -root <folder>` skips the picker. A bare path arg
  opens no window (AppKit treats it as a file to open).
- Apply rebuilds the `FileTree` (options are `let`); only `showHiddenFiles` applies live.
- The view is flat rows, not `List`: `ScrollView` + `LazyVStack(spacing: 0)` over
  `FileTree.visibleRows()` (depth-first, reads only expanded folders). macOS `List` adds row insets
  and a minimum height that break compact, gap-free rows and indent guides.
- ALL row geometry (height, indent, icon width, branch font) comes from `RowMetrics(fontSize:)`.
  Tune ratios there only. Indent guides are drawn per row at full height so segments join.
- The tree paints `.background(.background)` inside the theme environment; without it, a
  light-theme tree over a dark host is unreadable.
- To screenshot expanded folders without clicking: temporarily `setExpanded` paths in
  `DemoModel.rebuild`, capture, revert.
- `options.theme` (a SwiftUI `ColorScheme`, default `.dark`) is applied by `FileTreeView` via
  `.environment(\.colorScheme)`, scoped to the tree. Never `.preferredColorScheme` in the library:
  that changes the host's window. Default dark changed 0.1.0's follow-the-system look.
