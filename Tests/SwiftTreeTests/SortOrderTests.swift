import Foundation
import Testing

@testable import SwiftTree

@MainActor
struct SortOrderTests {
  let dir: TempDir
  let watcher = FakeWatcher()
  var root: URL { dir.url }

  /// Committed: a.txt, z.txt, b/keep.txt, sub/x.txt, sub/y.txt, gone/old.txt.
  /// Then: z.txt modified, y/new.txt untracked.
  init() throws {
    dir = try TempDir()
    try dir.make("a.txt", "z.txt", "b/keep.txt", "sub/x.txt", "sub/y.txt", "gone/old.txt")
    try git("init", "-q", in: dir.url)
    try git("add", ".", in: dir.url)
    try git("commit", "-qm", "init", in: dir.url)
    try "edit".write(to: dir.url.child("z.txt"), atomically: true, encoding: .utf8)
    try dir.make("y/new.txt")
  }

  func tree(_ configure: (inout FileTreeOptions) -> Void = { $0.sortOrder = .gitStatus }) async
    -> FileTree
  {
    var options = FileTreeOptions()
    configure(&options)
    let tree = FileTree(root: root, options: options, watcher: watcher, lister: Directory.list)
    await tree.started?.value
    return tree
  }

  func names(_ tree: FileTree, _ path: String = "") -> [String] {
    tree.children(of: path.isEmpty ? tree.root : tree.root.child(path)).map(\.name)
  }

  func gitDirChanged() throws {
    let gitDir = try git("rev-parse", "--absolute-git-dir", in: root)
      .trimmingCharacters(in: .newlines)
    watcher.emit(FileChangeBatch(paths: [URL(filePath: gitDir).child("index")]))
  }

  @Test func defaultIsAlphabeticalWhateverTheStatus() async {
    #expect(FileTreeOptions().sortOrder == .alphabetical)
    let tree = await tree { _ in }

    #expect(names(tree) == ["b", "gone", "sub", "y", "a.txt", "z.txt"])
  }

  @Test func changedFoldersThenChangedFilesThenTheRest() async {
    let tree = await tree()

    #expect(names(tree) == ["y", "z.txt", "b", "gone", "sub", "a.txt"])
  }

  @Test func stagedDeletedAndIgnoredGroupAsExpected() async throws {
    try "edit".write(to: root.child("a.txt"), atomically: true, encoding: .utf8)
    try git("add", "a.txt", in: root)  // staged only
    try FileManager.default.removeItem(at: root.child("gone/old.txt"))
    try ".hide\n".write(to: root.child(".gitignore"), atomically: true, encoding: .utf8)
    try git("add", ".gitignore", in: root)
    try git("commit", "-qm", "ignore", "--", ".gitignore", in: root)
    try dir.make(".hide", "b/.hide", "b/new.txt")
    let tree = await tree()

    #expect(tree.status(of: root.child("gone")) == .deleted)
    #expect(names(tree) == ["b", "gone", "y", "a.txt", "z.txt", "sub", ".gitignore", ".hide"])
    #expect(names(tree, "b") == ["new.txt", ".hide", "keep.txt"])  // ignored stays with untouched
  }

  @Test func nestedFoldersRegroupToo() async throws {
    try "edit".write(to: root.child("sub/y.txt"), atomically: true, encoding: .utf8)
    let tree = await tree()

    #expect(names(tree, "sub") == ["y.txt", "x.txt"])
  }

  @Test func orderFollowsStatusRefreshes() async throws {
    let tree = await tree()
    #expect(names(tree, "sub") == ["x.txt", "y.txt"])

    try "edit".write(to: root.child("sub/y.txt"), atomically: true, encoding: .utf8)
    try gitDirChanged()
    #expect(await eventually { names(tree, "sub") == ["y.txt", "x.txt"] })

    try git("commit", "-qam", "edit", in: root)
    try gitDirChanged()
    #expect(await eventually { names(tree, "sub") == ["x.txt", "y.txt"] })
  }

  @Test func withoutGitTheOrderIsAlphabetical() async {
    let tree = await tree {
      $0.sortOrder = .gitStatus
      $0.detectGit = false
    }

    #expect(names(tree) == ["b", "gone", "sub", "y", "a.txt", "z.txt"])
  }

  @Test func hiddenFilterStillApplies() async throws {
    try dir.make(".env")
    let tree = await tree {
      $0.sortOrder = .gitStatus
      $0.showHiddenFiles = false
    }

    #expect(tree.status(of: root.child(".env")) == .untracked)
    #expect(names(tree) == ["y", "z.txt", "b", "gone", "sub", "a.txt"])
  }
}
