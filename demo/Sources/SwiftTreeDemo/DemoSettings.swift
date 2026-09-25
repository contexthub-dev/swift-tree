import SwiftTree
import SwiftUI

/// Every knob the demo exposes. Equatable (unlike `FileTreeOptions`), so Apply
/// knows whether anything changed and whether a rebuild is needed.
struct DemoSettings: Equatable {
  var detectGit = true
  var canHaveMultipleGitRepositories = true
  var showHiddenFiles = true
  var showBranchNames = false
  var theme = ColorScheme.dark
  var showIndentGuides = true
  var fontSize: CGFloat = 12
  /// Empty: the system font.
  var fontFamily = ""
  var useDevIcons = true
  var useSingleColor = false
  var singleColor = StatusColors.zed.modified
  var modified = StatusColors.zed.modified
  var untracked = StatusColors.zed.untracked
  var staged = StatusColors.zed.staged
  var deleted = StatusColors.zed.deleted
  var ignored = StatusColors.zed.ignored
  var latency: TimeInterval = 0.3

  var isLatencyValid: Bool { (0.05...5.0).contains(latency) }

  var options: FileTreeOptions {
    var options = FileTreeOptions()
    options.detectGit = detectGit
    options.canHaveMultipleGitRepositories = canHaveMultipleGitRepositories
    options.showHiddenFiles = showHiddenFiles
    options.showBranchNames = showBranchNames
    options.theme = theme
    options.showIndentGuides = showIndentGuides
    options.fontSize = fontSize
    options.fontFamily = fontFamily.isEmpty ? nil : fontFamily
    options.useDevIcons = useDevIcons
    options.colors =
      useSingleColor
      ? StatusColors(all: singleColor)
      : StatusColors(
        modified: modified, untracked: untracked, staged: staged, deleted: deleted, ignored: ignored
      )
    return options
  }

  mutating func resetColors() {
    let zed = StatusColors.zed
    useSingleColor = false
    singleColor = zed.modified
    (modified, untracked, staged, deleted, ignored) =
      (zed.modified, zed.untracked, zed.staged, zed.deleted, zed.ignored)
  }

  /// Hidden files and theme are the options a live `FileTree` can change without a rebuild.
  func differsOnlyInLiveSettings(from other: DemoSettings) -> Bool {
    var same = self
    same.showHiddenFiles = other.showHiddenFiles
    same.theme = other.theme
    return same == other && self != other
  }
}
