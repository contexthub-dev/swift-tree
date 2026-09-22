import Foundation

/// One entry in the tree: a file, a folder, or a symlink.
public struct TreeNode: Identifiable, Hashable, Sendable {
  public let url: URL
  public let name: String
  /// False for symlinks, so a link to a folder is listed as a leaf and never followed.
  public let isDirectory: Bool
  public let isSymlink: Bool
  public var id: URL { url }
}

/// Lists one folder. Injected so tests can count or fake reads.
typealias DirectoryLister = @Sendable (URL) throws -> [TreeNode]

enum Directory {
  /// Children of `folder`: `.git` (folder or file) left out, folders before
  /// files, each group by name ignoring case. Hidden entries are kept; the
  /// tree filters them at display time so toggling needs no re-read.
  static let list: DirectoryLister = { folder in
    try FileManager.default.contentsOfDirectory(atPath: folder.path)
      .filter { $0 != ".git" }
      .map { name in
        let url = folder.child(name)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isSymlink = values?.isSymbolicLink ?? false
        return TreeNode(
          url: url, name: name,
          isDirectory: !isSymlink && (values?.isDirectory ?? false),
          isSymlink: isSymlink)
      }
      .sorted { a, b in
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.caseInsensitiveCompare(b.name) == .orderedAscending
      }
  }
}

extension URL {
  /// Every URL in the tree is built with this, from the root down, so one path
  /// always has one spelling (no trailing slash) and works as a dictionary key.
  func child(_ relativePath: some StringProtocol) -> URL {
    appending(path: String(relativePath), directoryHint: .notDirectory)
  }
}
