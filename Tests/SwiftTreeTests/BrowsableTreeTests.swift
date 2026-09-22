import Foundation
import Testing
import os

@testable import SwiftTree

struct DirectoryListTests {
  @Test func foldersFirstThenNameIgnoringCase() throws {
    let dir = try TempDir()
    try dir.make("b.txt", "A.txt", "zeta/", "Beta/", "alpha/")

    let names = try Directory.list(dir.url).map(\.name)

    #expect(names == ["alpha", "Beta", "zeta", "A.txt", "b.txt"])
  }

  @Test func gitFolderAndGitFileAreNeverListed() throws {
    let dir = try TempDir()
    try dir.make(".git/", "sub/.git", ".gitignore")

    #expect(try Directory.list(dir.url).map(\.name) == ["sub", ".gitignore"])
    #expect(try Directory.list(dir.url.child("sub")).isEmpty)
  }

  @Test func symlinkToFolderIsALeaf() throws {
    let dir = try TempDir()
    try dir.make("real/")
    try FileManager.default.createSymbolicLink(
      at: dir.url.child("link"), withDestinationURL: dir.url.child("real"))

    let link = try #require(try Directory.list(dir.url).first { $0.name == "link" })

    #expect(link.isSymlink)
    #expect(!link.isDirectory)
  }
}

@MainActor
struct FileTreeBrowsingTests {
  let root = URL(filePath: "/r")

  /// A lister over a fixed layout that records every folder it reads.
  func tree(_ layout: [String: [TreeNode]], reads: OSAllocatedUnfairLock<[String]>) -> FileTree {
    FileTree(root: root, options: .init(), watcher: FakeWatcher()) { url in
      reads.withLock { $0.append(url.path) }
      return layout[url.path] ?? []
    }
  }

  func node(_ path: String, dir: Bool = false) -> TreeNode {
    let url = URL(filePath: path, directoryHint: .notDirectory)
    return TreeNode(url: url, name: url.lastPathComponent, isDirectory: dir, isSymlink: false)
  }

  @Test func rootStartsExpandedAndOnlyAskedForFoldersAreRead() {
    let reads = OSAllocatedUnfairLock(initialState: [String]())
    let tree = tree(["/r": [node("/r/a", dir: true), node("/r/b", dir: true)]], reads: reads)

    #expect(tree.isExpanded(root))
    #expect(tree.children(of: root).map(\.name) == ["a", "b"])
    tree.setExpanded(root.child("a"), true)
    _ = tree.children(of: root.child("a"))
    _ = tree.children(of: root.child("a"))

    #expect(reads.withLock { $0 } == ["/r", "/r/a"])
  }

  @Test func hidingDotFilesKeepsExpansion() {
    let reads = OSAllocatedUnfairLock(initialState: [String]())
    let tree = tree(["/r": [node("/r/.env"), node("/r/src", dir: true)]], reads: reads)
    tree.setExpanded(root.child("src"), true)

    tree.showHiddenFiles = false
    #expect(tree.children(of: root).map(\.name) == ["src"])

    tree.showHiddenFiles = true
    #expect(tree.children(of: root).map(\.name) == [".env", "src"])
    #expect(tree.isExpanded(root.child("src")))
    #expect(reads.withLock { $0 } == ["/r"])
  }
}
