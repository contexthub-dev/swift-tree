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

  @Test func dsStoreIsNeverShown() {
    let tree = tree(
      ["/r": [node("/r/.DS_Store"), node("/r/.env")]], reads: .init(initialState: []))
    #expect(tree.children(of: root).map(\.name) == [".env"])
    tree.showHiddenFiles = false
    #expect(tree.children(of: root).isEmpty)
  }
}

@MainActor
struct VisibleRowsTests {
  let root = URL(filePath: "/r")
  let layout: [String: [TreeNode]] = [
    "/r": [dir("/r/a"), dir("/r/b"), file("/r/.env"), file("/r/x.txt")],
    "/r/a": [dir("/r/a/c"), file("/r/a/.hidden"), file("/r/a/y.txt")],
    "/r/a/c": [file("/r/a/c/z.txt")],
    "/r/b": [file("/r/b/never.txt")],
  ]

  static func dir(_ path: String) -> TreeNode { node(path, isDirectory: true) }
  static func file(_ path: String) -> TreeNode { node(path, isDirectory: false) }
  static func node(_ path: String, isDirectory: Bool) -> TreeNode {
    let url = URL(filePath: path, directoryHint: .notDirectory)
    return TreeNode(
      url: url, name: url.lastPathComponent, isDirectory: isDirectory, isSymlink: false)
  }

  func tree(reads: OSAllocatedUnfairLock<[String]>) -> FileTree {
    FileTree(root: root, options: .init(), watcher: FakeWatcher()) { url in
      reads.withLock { $0.append(url.path) }
      return layout[url.path] ?? []
    }
  }

  @Test func rowsAreDepthFirstWithDepthsAndSkipCollapsedFolders() {
    let reads = OSAllocatedUnfairLock(initialState: [String]())
    let tree = tree(reads: reads)
    tree.setExpanded(root.child("a"), true)
    tree.setExpanded(root.child("a").child("c"), true)

    let rows = tree.visibleRows().map { "\($0.depth) \($0.node.name)" }

    #expect(
      rows == [
        "0 r", "1 a", "2 c", "3 z.txt", "2 .hidden", "2 y.txt", "1 b", "1 .env", "1 x.txt",
      ])
    #expect(!reads.withLock { $0 }.contains("/r/b"))
  }

  @Test func hiddenFilesAreFilteredAtEveryDepth() {
    let reads = OSAllocatedUnfairLock(initialState: [String]())
    let tree = tree(reads: reads)
    tree.setExpanded(root.child("a"), true)
    tree.showHiddenFiles = false

    let names = tree.visibleRows().map(\.node.name)

    #expect(!names.contains(".env") && !names.contains(".hidden"))
    #expect(names.contains("y.txt"))
  }
}

struct RowMetricsTests {
  @Test func twelvePointMatchesZed() {
    let m = RowMetrics(fontSize: 12)
    #expect(m.rowHeight == 20 && m.indent == 16)
  }

  @Test func geometryScalesWithFontSize() {
    let m = RowMetrics(fontSize: 18)
    #expect(m.rowHeight == 30 && m.indent == 24)
  }
}
