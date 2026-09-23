# swift-tree

A SwiftUI file tree for macOS apps, like the project navigator in an IDE. It
colors every file and folder by its git status and keeps up with changes on
disk and in git. Nested repositories are supported.

- macOS 14+, SwiftUI (AppKit hosts embed it with `NSHostingView`)
- No dependencies outside Apple frameworks
- Uses the `git` CLI (2.30+) found on `PATH`
- Apache 2.0

## Install

```swift
.package(url: "https://github.com/contexthub-dev/swift-tree.git", from: "0.1.0")
```

and add `"SwiftTree"` to your target's dependencies.

## Embed

```swift
import SwiftTree
import SwiftUI

struct Sidebar: View {
  @State private var tree = FileTree(
    root: URL(fileURLWithPath: "/path/to/project"),
    onError: { error in print("swift-tree:", error) }
  )

  var body: some View {
    FileTreeView(tree: tree) { item in
      // Left click: files select, folders also toggle open.
      if !item.isDirectory { open(item.url) }
    } rightClickMenu: { item in
      Button("Reveal in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
      }
      Button("Copy Relative Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.relativePath, forType: .string)
      }
    }
  }

  func open(_ url: URL) { /* … */ }
}
```

Each click handler gets a `TreeItemInfo`: absolute `url`, `relativePath` from the
tree root, `isDirectory`, `repoRoot`, and `gitStatus`.

## Options

```swift
var options = FileTreeOptions()
options.detectGit = true                        // false: no colors, no git calls
options.canHaveMultipleGitRepositories = true   // false: ignore nested repos
options.showHiddenFiles = true                  // toggle later via tree.showHiddenFiles
options.showBranchNames = false                 // label repo-root folders with their branch
options.theme = .dark                           // .light or .dark, regardless of system appearance
options.showIndentGuides = true                 // vertical lines beside open folders' contents
options.fontSize = 12                           // 8-32; row height and indent scale with it
options.colors.modified = .orange               // override any status color
options.colors = StatusColors(all: .orange)     // one color for every change; ignored stays gray

let tree = FileTree(root: root, options: options)
```

`.git` is never shown. Symlinks are listed but not followed.

## Watching

By default the tree creates its own FSEvents watcher. To share one across your
app, pass anything conforming to `FileWatching` (e.g. one `FSEventsWatcher`):

```swift
let watcher = FSEventsWatcher()
let tree = FileTree(root: root, watcher: watcher)

tree.pause()        // stop following file changes; git status still updates
await tree.resume() // re-read the tree, keep open folders open, watch again
```

## Status API

Use git status without the view:

```swift
let sub = try tree.register(path: root.appending(path: "Sources")) { changes in
  // First call: every file and folder under the path. Then: only what changed.
}
tree.unregister(sub)

let all = try await tree.snapshot(of: root)  // [URL: GitStatus], incl. deleted files
```

Paths outside the root, or any call with `detectGit = false`, throw
`FileTreeError`.

## Demo

`demo/` is a small app for trying every option by hand: pick a folder, change
settings and click Apply, pause and resume watching, and watch clicks, errors
and status callbacks as they happen.

```sh
make demo                   # choose a folder in the app
make demo ROOT=~/code/my-repo
```

## Developing and releasing

File-type icons come from [devicon](https://github.com/devicons/devicon) (MIT).
Its font isn't committed to `main`. Fetch the latest release before building:

```sh
make fonts    # downloads into Sources/SwiftTree/Resources/DevIcons (gitignored)
make test
```

Without it everything still builds, but file rows show the generic `doc` icon
and `FileTree` reports `.devIconsUnavailable` once. CI runs `make fonts` first.

Releases come only from the **Release** workflow (Actions → Release → Run
workflow, enter `X.Y.Z`). It fetches the latest devicon, runs the tests, commits
the font on a release-only commit on top of `main`, and pushes just the tag.
So each tag carries its font, and `main` never does. Don't push tags by hand:
the tag would have no font.
