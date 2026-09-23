import Foundation
import Testing
import os

@testable import SwiftTree

/// Runs against real git in a temp folder laid out like the spec's example:
/// the root is a repo, folder11 is a nested repo, folder12 and folder13 are plain.
@MainActor
struct GitStatusEngineTests {
  let dir: TempDir
  let watcher = FakeWatcher()
  var root: URL { dir.url }

  init() throws {
    dir = try TempDir()
    try dir.make("tracked.txt", "folder12/f.txt", "folder13/q.txt", "folder11/n.txt")
    try git("init", "-q", in: root)
    try git("add", "tracked.txt", "folder12", in: root)
    try git("commit", "-qm", "init", in: root)
    try git("init", "-q", in: root.child("folder11"))
    try "edit".write(to: root.child("folder12/f.txt"), atomically: true, encoding: .utf8)
  }

  func tree(_ configure: (inout FileTreeOptions) -> Void = { _ in }) async -> FileTree {
    var options = FileTreeOptions()
    configure(&options)
    let tree = FileTree(root: root, options: options, watcher: watcher, lister: Directory.list)
    await tree.started?.value
    return tree
  }

  /// Fires the git-dir watch the way FSEvents would after a git command.
  func gitDirChanged(_ repo: URL) throws {
    let gitDir = try git("rev-parse", "--absolute-git-dir", in: repo)
      .trimmingCharacters(in: .newlines)
    watcher.emit(FileChangeBatch(paths: [URL(filePath: gitDir).child("index")]))
  }

  @Test func filesTakeStatusFromTheNearestRepo() async {
    let tree = await tree()

    #expect(tree.repoRoot(of: root.child("folder11/n.txt")) == root.child("folder11"))
    #expect(tree.status(of: root.child("folder11/n.txt")) == .untracked)
    #expect(tree.repoRoot(of: root.child("folder12/f.txt")) == root)
    #expect(tree.status(of: root.child("folder12/f.txt")) == .modified)
    #expect(tree.status(of: root.child("folder12")) == .modified)
    #expect(tree.status(of: root.child("folder13/q.txt")) == .untracked)
    #expect(tree.status(of: root.child("tracked.txt")) == .unmodified)
  }

  @Test func withNestingOffEverythingResolvesAgainstTheOuterRepo() async {
    let tree = await tree { $0.canHaveMultipleGitRepositories = false }

    #expect(tree.repoRoot(of: root.child("folder11/n.txt")) == root)
    #expect(tree.status(of: root.child("folder11/n.txt")) == .untracked)
    #expect(watcher.active == 2)  // tree watch + the one repo's git dir
  }

  @Test func gitInitInASubfolderMakesItARepoRoot() async throws {
    let tree = await tree()
    try git("init", "-q", in: root.child("folder13"))

    tree.apply(FileChangeBatch(paths: [root.child("folder13/.git/HEAD")]))

    #expect(
      await eventually { tree.repoRoot(of: root.child("folder13/q.txt")) == root.child("folder13") }
    )
  }

  @Test func cleanSubmoduleIsFoundThroughGitmodules() async throws {
    try dir.make("vendor/lib/x.txt")
    let lib = root.child("vendor/lib")
    try git("init", "-q", in: lib)
    try git("add", "x.txt", in: lib)
    try git("commit", "-qm", "lib", in: lib)
    try "[submodule \"lib\"]\n\tpath = vendor/lib\n\turl = ./vendor/lib\n"
      .write(to: root.child(".gitmodules"), atomically: true, encoding: .utf8)
    try git("add", ".gitmodules", "vendor/lib", in: root)
    try git("commit", "-qm", "sub", in: root)

    let tree = await tree()

    #expect(tree.repoRoot(of: lib.child("x.txt")) == lib)
  }

  @Test func gitignoredRepoIsStillANestedRepo() async throws {
    try dir.make("ignored/x.txt")
    try git("init", "-q", in: root.child("ignored"))
    try "ignored/\n".write(to: root.child(".gitignore"), atomically: true, encoding: .utf8)

    let tree = await tree()

    #expect(tree.repoRoot(of: root.child("ignored/x.txt")) == root.child("ignored"))
    #expect(tree.status(of: root.child("ignored/x.txt")) == .untracked)
  }

  @Test func detectGitOffRunsNoGit() async throws {
    let calls = OSAllocatedUnfairLock(initialState: 0)
    var options = FileTreeOptions()
    options.detectGit = false
    let tree = FileTree(
      root: root, options: options, watcher: watcher, lister: Directory.list,
      git: { args, cwd in
        calls.withLock { $0 += 1 }
        return try Git.runBlocking(args, cwd)
      })

    #expect(tree.status(of: root.child("folder12/f.txt")) == nil)
    #expect(throws: FileTreeError.gitDetectionDisabled) { try tree.register(path: root) { _ in } }
    await #expect(throws: FileTreeError.gitDetectionDisabled) { try await tree.snapshot(of: root) }
    #expect(calls.withLock { $0 } == 0)
  }

  @Test func pathOutsideTheRootIsRejected() async {
    let tree = await tree()
    let outside = root.parent

    #expect(throws: FileTreeError.pathOutsideRoot(outside)) {
      try tree.register(path: outside) { _ in }
    }
  }

  @Test func registerGetsEverythingThenOnlyChangesUnderItsPath() async throws {
    let tree = await tree()
    var rootCalls: [[URL: GitStatus]] = []
    var folder12Calls: [[URL: GitStatus]] = []
    _ = try tree.register(path: root) { rootCalls.append($0) }
    _ = try tree.register(path: root.child("folder12")) { folder12Calls.append($0) }
    #expect(await eventually { rootCalls.count == 1 && folder12Calls.count == 1 })
    #expect(rootCalls[0][root.child("tracked.txt")] == .unmodified)
    #expect(rootCalls[0][root.child("folder12/f.txt")] == .modified)
    #expect(folder12Calls[0].keys.allSatisfy { root.child("folder12").encloses($0) })

    try "edit".write(to: root.child("tracked.txt"), atomically: true, encoding: .utf8)
    try git("add", "tracked.txt", in: root)
    try gitDirChanged(root)

    #expect(await eventually { rootCalls.count == 2 })
    #expect(rootCalls[1] == [root.child("tracked.txt"): .staged])
    #expect(folder12Calls.count == 1)
  }

  @Test func unregisteredCallbackIsNotCalledAgain() async throws {
    let tree = await tree()
    var calls = 0
    let subscription = try tree.register(path: root) { _ in calls += 1 }
    #expect(await eventually { calls == 1 })

    tree.unregister(subscription)
    try git("add", "folder12/f.txt", in: root)
    try gitDirChanged(root)

    #expect(await eventually { tree.status(of: root.child("folder12/f.txt")) == .staged })
    #expect(calls == 1)
  }

  @Test func snapshotIncludesTrackedDeletedFilesAndFolders() async throws {
    let tree = await tree()
    try FileManager.default.removeItem(at: root.child("tracked.txt"))
    tree.apply(FileChangeBatch(paths: [root.child("tracked.txt")]))
    #expect(await eventually { tree.status(of: root) == .deleted })

    let snapshot = try await tree.snapshot(of: root)

    #expect(snapshot[root.child("tracked.txt")] == .deleted)
    #expect(snapshot[root.child("folder12")] == .modified)
    #expect(snapshot[root.child("folder11/n.txt")] == .untracked)
  }
}

/// The spec's headline case, end to end with real FSEvents.
@MainActor
struct GitWhilePausedTests {
  @Test func gitAddUpdatesStatusWithinASecondWhilePaused() async throws {
    let dir = try TempDir()
    try dir.make("a.txt")
    try git("init", "-q", in: dir.url)
    try git("add", "a.txt", in: dir.url)
    try git("commit", "-qm", "a", in: dir.url)
    try "edit".write(to: dir.url.child("a.txt"), atomically: true, encoding: .utf8)
    let tree = FileTree(root: dir.url)
    await tree.started?.value
    #expect(tree.status(of: dir.url.child("a.txt")) == .modified)
    tree.pause()
    try await Task.sleep(for: .milliseconds(200))  // let FSEvents settle before acting

    try git("add", "a.txt", in: dir.url)

    #expect(
      await eventually(within: .seconds(1)) { tree.status(of: dir.url.child("a.txt")) == .staged })
  }
}
