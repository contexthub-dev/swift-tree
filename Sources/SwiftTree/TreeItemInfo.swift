import Foundation

/// What a click handler learns about the clicked row.
public struct TreeItemInfo: Sendable, Hashable {
  /// Absolute.
  public let url: URL
  /// Relative to `FileTree.root`, no leading "/". Empty for the root itself.
  public let relativePath: String
  /// False for symlinks, like `TreeNode`.
  public let isDirectory: Bool
  public let isSymlink: Bool
  /// The deepest repo containing it; nil if none, or git is off or unavailable.
  public let repoRoot: URL?
  /// Rolled up for folders; nil when `repoRoot` is nil.
  public let gitStatus: GitStatus?
}
