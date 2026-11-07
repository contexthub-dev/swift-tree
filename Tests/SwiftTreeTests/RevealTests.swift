import Foundation
import Testing

@testable import SwiftTree

@MainActor
struct RevealTests {
  let dir: TempDir
  var root: URL { dir.url }

  init() throws {
    dir = try TempDir()
    try dir.make("src/app/main.swift", "docs/a.md")
  }

  func tree() -> FileTree {
    var options = FileTreeOptions()
    options.detectGit = false
    return FileTree(root: root, options: options, watcher: FakeWatcher(), lister: Directory.list)
  }

  @Test func opensAncestorsSelectsAndTargetsTheFile() {
    let tree = tree()
    let file = root.child("src/app/main.swift")

    tree.reveal(file)

    #expect(tree.isExpanded(root.child("src")))
    #expect(tree.isExpanded(root.child("src/app")))
    #expect(!tree.isExpanded(root.child("docs")))
    #expect(tree.visibleRows().contains { $0.node?.url == file })
    #expect(tree.selection == file)
    #expect(tree.revealTarget == file)
  }

  @Test func leavesFoldersTheUserOpenedOpen() {
    let tree = tree()
    tree.setExpanded(root.child("docs"), true)

    tree.reveal(root.child("src/app/main.swift"))

    #expect(tree.isExpanded(root.child("docs")))
  }

  @Test func urlOutsideTheRootOnlySelects() {
    let tree = tree()
    let outside = URL(filePath: "/tmp/elsewhere.txt")

    tree.reveal(outside)

    #expect(tree.selection == outside)
    #expect(tree.revealTarget == nil)
    #expect(!tree.isExpanded(root.child("src")))
  }

  @Test func nilClearsTheSelection() {
    let tree = tree()
    tree.reveal(root.child("docs/a.md"))

    tree.reveal(nil)

    #expect(tree.selection == nil)
  }
}
