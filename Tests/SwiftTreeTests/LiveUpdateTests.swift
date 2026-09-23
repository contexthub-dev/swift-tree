import Foundation
import Testing

@testable import SwiftTree

@MainActor
struct LiveUpdateTests {
  let dir: TempDir
  let watcher = FakeWatcher()
  let tree: FileTree

  init() throws {
    dir = try TempDir()
    try dir.make("a/one.txt", "b/")
    tree = FileTree(root: dir.url, options: .init(), watcher: watcher, lister: Directory.list)
  }

  func names(_ path: String = "") -> [String] {
    tree.children(of: path.isEmpty ? tree.root : tree.root.child(path)).map(\.name)
  }

  @Test func hostWatcherIsTheOnlyWatchAndCoversTheRoot() {
    #expect(watcher.watched == [[tree.root]])
    #expect(watcher.active == 1)
  }

  @Test func batchReListsTheLoadedParent() throws {
    #expect(names("a") == ["one.txt"])
    try dir.make("a/two.txt")

    tree.apply(FileChangeBatch(paths: [tree.root.child("a/two.txt")]))

    #expect(names("a") == ["one.txt", "two.txt"])
  }

  @Test func resolvedSpellingOfTheRootIsMapped() throws {
    _ = names()
    try dir.make("c/")
    let resolved = URL(filePath: dir.url.resolvingSymlinksInPath().path)
    let real = URL(filePath: "/private" + resolved.path)  // /var → /private/var

    tree.apply(FileChangeBatch(paths: [real.child("c")]))

    #expect(names() == ["a", "b", "c"])
  }

  @Test func gitPathsAreIgnored() throws {
    _ = names()
    try dir.make(".git/index")

    tree.apply(FileChangeBatch(paths: [tree.root.child(".git/index")]))

    #expect(names() == ["a", "b"])  // not re-listed, so the new .git never shows up anyway
  }

  @Test func pauseCancelsTheWatchAndFreezesTheTree() throws {
    _ = names()
    tree.pause()
    try dir.make("c/")

    tree.apply(FileChangeBatch(paths: [tree.root.child("c")]))

    #expect(watcher.active == 0)
    #expect(tree.isPaused)
    #expect(names() == ["a", "b"])
  }

  @Test func resumeMatchesDiskAndKeepsSurvivingFoldersOpen() async throws {
    for folder in ["a", "b"] { tree.setExpanded(tree.root.child(folder), true) }
    _ = names("a")
    tree.pause()
    try FileManager.default.removeItem(at: dir.url.child("b"))
    try dir.make("a/new.txt")

    await tree.resume()

    #expect(tree.isExpanded(tree.root.child("a")))
    #expect(!tree.isExpanded(tree.root.child("b")))
    #expect(names() == ["a"])
    #expect(names("a") == ["new.txt", "one.txt"])
    #expect(watcher.active == 1)
  }

  @Test func deletedRootIsReportedMissing() throws {
    try FileManager.default.removeItem(at: dir.url)

    tree.apply(FileChangeBatch(paths: [tree.root], rootChanged: true))

    #expect(tree.rootMissing)
  }
}

struct FSEventsWatcherTests {
  @Test func reportsACreatedFileWithinASecond() async throws {
    let dir = try TempDir()
    let (batches, sink) = AsyncStream.makeStream(of: FileChangeBatch.self)
    let token = FSEventsWatcher(latency: 0.1).watch([dir.url]) { sink.yield($0) }
    defer { token.cancel() }
    try await Task.sleep(for: .milliseconds(200))  // FSEvents needs a moment before it reports

    try dir.make("new.txt")

    let batch = try await firstBatch(batches, containing: "new.txt", within: .seconds(1))
    #expect(batch != nil)
  }

  func firstBatch(
    _ batches: AsyncStream<FileChangeBatch>, containing name: String, within limit: Duration
  ) async throws -> FileChangeBatch? {
    try await withThrowingTaskGroup(of: FileChangeBatch?.self) { group in
      group.addTask {
        for await batch in batches
        where batch.paths.contains(where: { $0.lastPathComponent == name }) {
          return batch
        }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: limit)
        return nil
      }
      let first = try await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }
}
