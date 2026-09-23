import SwiftUI

/// How a `FileTree` behaves. Every default matches the common IDE case.
public struct FileTreeOptions: Sendable {
  /// Off: no status colors, no branch labels, and no git command ever runs.
  public var detectGit = true
  /// Off: nested repos are ignored and everything resolves against the repo containing the root.
  public var canHaveMultipleGitRepositories = true
  /// Initial value of `FileTree.showHiddenFiles`.
  public var showHiddenFiles = true
  /// Label each repo-root folder with its branch (or short SHA when detached).
  public var showBranchNames = false
  /// Light or dark rendering of the tree, independent of the system appearance.
  public var theme = ColorScheme.dark
  /// Override any status color: `options.colors.modified = .orange`.
  public var colors = StatusColors.zed
  public init() {}
}
