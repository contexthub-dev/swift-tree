import Foundation
import Testing

@testable import SwiftTree

@MainActor
struct ClickTests {
  let dir: TempDir
  var root: URL { dir.url }

  init() throws {
    dir = try TempDir()
    try dir.make("src/a.txt", "folder11/n.txt")
    try git("init", "-q", in: root)
    try git("init", "-q", in: root.child("folder11"))
  }

  func tree(detectGit: Bool = true) async -> FileTree {
    var options = FileTreeOptions()
    options.detectGit = detectGit
    let tree = FileTree(
      root: root, options: options, watcher: FakeWatcher(), lister: Directory.list)
    await tree.started?.value
    _ = tree.children(of: root)
    return tree
  }

  @Test func fileInfoCarriesPathsKindRepoAndStatus() async {
    let tree = await tree()
    _ = tree.children(of: root.child("src"))

    let info = tree.info(for: root.child("src/a.txt"))

    #expect(info.relativePath == "src/a.txt")
    #expect(!info.isDirectory)
    #expect(info.repoRoot == root)
    #expect(info.gitStatus == .untracked)
  }

  @Test func fileUnderANestedRepoReportsThatRepo() async {
    let tree = await tree()
    _ = tree.children(of: root.child("folder11"))

    #expect(tree.info(for: root.child("folder11/n.txt")).repoRoot == root.child("folder11"))
  }

  @Test func gitOffLeavesRepoAndStatusEmpty() async {
    let info = await tree(detectGit: false).info(for: root.child("src"))

    #expect(info.isDirectory)
    #expect(info.repoRoot == nil)
    #expect(info.gitStatus == nil)
  }

  @Test func outsideAnyRepoLeavesRepoAndStatusEmpty() async throws {
    let plain = try TempDir()
    try plain.make("x.txt")
    let tree = FileTree(
      root: plain.url, options: .init(), watcher: FakeWatcher(), lister: Directory.list)
    await tree.started?.value

    let info = tree.info(for: plain.url.child("x.txt"))

    #expect(info.repoRoot == nil)
    #expect(info.gitStatus == nil)
  }

  @Test func selectingAFolderTogglesItAndAFileDoesNot() async throws {
    let tree = await tree()
    let src = try #require(tree.children(of: root).first { $0.name == "src" })

    tree.select(src)
    #expect(tree.selection == src.url)
    #expect(tree.isExpanded(src.url))
    tree.select(src)
    #expect(!tree.isExpanded(src.url))
  }
}
