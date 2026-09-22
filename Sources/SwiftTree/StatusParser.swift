import Foundation

/// One repo's `git status --porcelain=v2 -z --branch` output, parsed.
struct PorcelainStatus: Equatable {
  /// Nil when HEAD is detached; `oid` is used then.
  var branch: String?
  var oid: String?
  /// Repo-relative paths; folders end in "/" (a nested repo, or an ignored folder).
  var entries: [String: GitStatus] = [:]
  /// Untracked "dir/" entries. With `-uall` git reports a folder whole only when it's a nested repo.
  var nestedRepoCandidates: [String] = []
}

enum StatusParser {
  static func parse(_ data: Data) -> PorcelainStatus {
    var result = PorcelainStatus()
    var records = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }[...]
    while let record = records.popFirst() {
      switch record.first {
      case "#":
        let header = record.split(separator: " ", maxSplits: 2).map(String.init)
        guard header.count == 3 else { continue }
        if header[1] == "branch.head" {
          result.branch = header[2] == "(detached)" ? nil : header[2]
        }
        if header[1] == "branch.oid" { result.oid = header[2] }
      case "1":  // 1 XY sub mH mI mW hH hI path
        let fields = record.split(separator: " ", maxSplits: 8)
        result.entries[String(fields[8])] = status(fields[1])
      case "2":  // 2 XY sub mH mI mW hH hI Xscore path, then origPath as its own record
        let fields = record.split(separator: " ", maxSplits: 9)
        result.entries[String(fields[9])] = status(fields[1])
        _ = records.popFirst()
      case "u":  // unmerged: conflicts read as modified
        let fields = record.split(separator: " ", maxSplits: 10)
        result.entries[String(fields[10])] = .modified
      case "?":
        let path = String(record.dropFirst(2))
        result.entries[path] = .untracked
        if path.hasSuffix("/") { result.nestedRepoCandidates.append(path) }
      case "!":
        result.entries[String(record.dropFirst(2))] = .ignored
      default:
        continue
      }
    }
    return result
  }

  /// X = index, Y = worktree. Order matters: worktree state wins, so a
  /// staged-then-edited file reads as modified.
  static func status(_ xy: Substring) -> GitStatus {
    let x = xy.first
    let y = xy.last
    if y == "D" { return .deleted }
    if y == "M" || y == "T" { return .modified }
    if x == "D" { return .deleted }
    if let x, "MARCT".contains(x) { return .staged }
    return .unmodified
  }
}
