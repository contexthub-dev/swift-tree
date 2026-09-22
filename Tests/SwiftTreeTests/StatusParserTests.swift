import Foundation
import Testing

@testable import SwiftTree

struct StatusParserTests {
  /// Captured from git 2.50 on a repo holding one file in each state, NULs shown as "\0".
  static let fixture =
    [
      "# branch.oid 1946b224f4509354d00c04a3d19aa63b65fd8d72",
      "# branch.head main",
      "1 .D N... 100644 100644 000000 4bcf 4bcf deleted.txt",
      "2 R. N... 100644 100644 100644 f2ad f2ad R100 renamed2.txt", "renamed.txt",
      "1 A. N... 000000 100644 100644 0000 fa49 sp ace.txt",
      "1 D. N... 100644 000000 000000 d905 0000 staged_del.txt",
      "1 MM N... 100644 100644 100644 6178 7de6 staged_then_edit.txt",
      "1 .M N... 100644 100644 100644 7898 7898 tracked.txt",
      "u UU N... 100644 100644 100644 100644 7898 f2ad 6178 conflicted.txt",
      "? folder11/",
      "? folder13/q.txt",
      "! a.log",
      "! node_modules/",
    ].joined(separator: "\0") + "\0"

  @Test func mapsEveryEntryPerTheXYTable() {
    let status = StatusParser.parse(Data(Self.fixture.utf8))

    #expect(
      status.entries == [
        "deleted.txt": .deleted,
        "renamed2.txt": .staged,
        "sp ace.txt": .staged,
        "staged_del.txt": .deleted,
        "staged_then_edit.txt": .modified,
        "tracked.txt": .modified,
        "conflicted.txt": .modified,
        "folder11/": .untracked,
        "folder13/q.txt": .untracked,
        "a.log": .ignored,
        "node_modules/": .ignored,
      ])
    #expect(status.nestedRepoCandidates == ["folder11/"])
    #expect(status.branch == "main")
  }

  @Test func detachedHeadHasNoBranchButKeepsTheOid() {
    let data = Data("# branch.oid 0e1ceaf4\0# branch.head (detached)\0".utf8)

    let status = StatusParser.parse(data)

    #expect(status.branch == nil)
    #expect(status.oid == "0e1ceaf4")
  }
}

struct StatusRollupTests {
  let repo = URL(filePath: "/r")

  @Test func folderTakesTheHighestPriorityBeneathIt() {
    let files: [URL: GitStatus] = [
      repo.child("a/b/new.txt"): .untracked,
      repo.child("a/b/gone.txt"): .deleted,
      repo.child("a/edit.txt"): .modified,
      repo.child("c/staged.txt"): .staged,
    ]

    let map = StatusRollup.rollUp(files, repoRoot: repo)

    #expect(map[repo.child("a/b")] == .deleted)
    #expect(map[repo.child("a")] == .deleted)
    #expect(map[repo.child("c")] == .staged)
    #expect(map[repo] == .deleted)
  }

  @Test func ignoredDoesNotRollUp() {
    let map = StatusRollup.rollUp([repo.child("a/x.log"): .ignored], repoRoot: repo)

    #expect(map[repo.child("a")] == nil)
  }

  @Test func lookupFallsBackToACoveringFolderThenUnmodified() {
    let covering: [URL: GitStatus] = [repo.child("node_modules"): .ignored]

    #expect(
      StatusRollup.lookup(
        repo.child("node_modules/x/y.js"), in: covering, covering: covering, repoRoot: repo)
        == .ignored)
    #expect(
      StatusRollup.lookup(repo.child("src/a.swift"), in: [:], covering: covering, repoRoot: repo)
        == .unmodified)
  }
}
