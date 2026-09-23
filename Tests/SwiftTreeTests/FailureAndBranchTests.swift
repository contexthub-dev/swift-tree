import Foundation
import Testing

@testable import SwiftTree

@MainActor
struct BranchLabelTests {
  let dir: TempDir
  var root: URL { dir.url }

  init() throws {
    dir = try TempDir()
    try dir.make("a.txt", "plain/b.txt")
    try git("init", "-q", "-b", "main", in: root)
    try git("add", "a.txt", in: root)
    try git("commit", "-qm", "a", in: root)
  }

  func tree(showBranchNames: Bool) async -> FileTree {
    var options = FileTreeOptions()
    options.showBranchNames = showBranchNames
    let tree = FileTree(
      root: root, options: options, watcher: FakeWatcher(), lister: Directory.list)
    await tree.started?.value
    return tree
  }

  @Test func offByDefault() async {
    #expect(await tree(showBranchNames: false).branch(of: root) == nil)
  }

  @Test func onlyRepoRootsAreLabelled() async {
    let tree = await tree(showBranchNames: true)

    #expect(tree.branch(of: root) == "main")
    #expect(tree.branch(of: root.child("plain")) == nil)
  }

  @Test func detachedHeadShowsTheShortSHA() async throws {
    try git("checkout", "-q", "--detach", in: root)
    let sha = try git("rev-parse", "--short=7", "HEAD", in: root).trimmingCharacters(in: .newlines)

    #expect(await tree(showBranchNames: true).branch(of: root) == sha)
  }
}

@MainActor
struct GitFailureTests {
  let dir: TempDir
  var root: URL { dir.url }

  init() throws {
    dir = try TempDir()
    try dir.make("a.txt", "inner/b.txt")
    try git("init", "-q", in: root)
    try git("init", "-q", in: root.child("inner"))
  }

  @Test func missingGitIsReportedOnceAndLeavesNoColors() async {
    var errors: [FileTreeError] = []
    let tree = FileTree(
      root: root, options: .init(), watcher: FakeWatcher(), lister: Directory.list,
      git: { args, _ in throw GitError(args: args, exitCode: 127, stderr: "not found") },
      onError: { errors.append($0) })
    await tree.started?.value

    tree.apply(FileChangeBatch(paths: [root.child("a.txt")]))
    try? await Task.sleep(for: .milliseconds(50))

    #expect(errors == [.gitUnavailable])
    #expect(tree.status(of: root.child("a.txt")) == nil)
    #expect(tree.children(of: root).map(\.name) == ["inner", "a.txt"])
  }

  @Test func oneFailingRepoIsReportedOnceAndOthersKeepTheirStatus() async throws {
    let inner = root.child("inner")
    var errors: [FileTreeError] = []
    let watcher = FakeWatcher()
    let tree = FileTree(
      root: root, options: .init(), watcher: watcher, lister: Directory.list,
      git: { args, cwd in
        if cwd == inner, args.contains("status") {
          throw GitError(args: args, exitCode: 128, stderr: "broken")
        }
        return try Git.runBlocking(args, cwd)
      },
      onError: { errors.append($0) })
    await tree.started?.value

    await tree.resume()  // not paused: no-op
    tree.pause()
    await tree.resume()  // refreshes every repo again

    #expect(errors.count == 1)
    #expect(errors.first.map { if case .gitFailed(inner, _) = $0 { true } else { false } } == true)
    #expect(tree.status(of: root.child("a.txt")) == .untracked)
    #expect(tree.status(of: inner.child("b.txt")) == .unmodified)
  }
}
