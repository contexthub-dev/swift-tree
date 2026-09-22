import Foundation

enum StatusRollup {
  /// High → low. Ignored and unmodified never roll up.
  static let priority: [GitStatus] = [.deleted, .modified, .staged, .untracked]

  /// `files` plus every folder above them up to and including `repoRoot`,
  /// each folder taking the highest-priority status beneath it.
  static func rollUp(_ files: [URL: GitStatus], repoRoot: URL) -> [URL: GitStatus] {
    var result = files
    for (url, status) in files {
      guard let rank = priority.firstIndex(of: status) else { continue }
      var folder = url.parent
      while repoRoot.encloses(folder) {
        // Once a folder already ranks as high, everything above it does too.
        if let current = result[folder], let held = priority.firstIndex(of: current), held <= rank {
          break
        }
        result[folder] = status
        if folder == repoRoot { break }
        folder = folder.parent
      }
    }
    return result
  }

  /// A path's own entry, else the status of a folder git reported whole
  /// (an ignored folder, or an untracked nested repo when nesting is off),
  /// else unmodified.
  static func lookup(
    _ url: URL, in map: [URL: GitStatus], covering: [URL: GitStatus], repoRoot: URL
  ) -> GitStatus {
    if let status = map[url] { return status }
    var folder = url.parent
    while repoRoot.encloses(folder) {
      if let status = covering[folder] { return status }
      if folder == repoRoot { break }
      folder = folder.parent
    }
    return .unmodified
  }
}
