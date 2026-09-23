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
  /// Vertical guide lines beside the contents of each open folder.
  public var showIndentGuides = true
  /// Point size of row names; icons, branch labels, row height and indent scale with it.
  /// Clamped to 8...32.
  public var fontSize: CGFloat {
    get { _fontSize }
    set { _fontSize = min(max(newValue, 8), 32) }
  }
  private var _fontSize: CGFloat = 12
  /// devicon file-type glyphs on file rows; `doc` when off, unmapped, or the font is missing.
  public var useDevIcons = true
  /// Override any status color: `options.colors.modified = .orange`.
  public var colors = StatusColors.zed
  public init() {}
}
