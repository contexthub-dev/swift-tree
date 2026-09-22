import Foundation
import Observation

/// The tree's state: which folders are open, what they contain, and (later)
/// their git status. `FileTreeView` draws it; hosts can also use it without the view.
@MainActor @Observable
public final class FileTree {
  public let root: URL
  /// Dot-named entries. Toggling re-filters what is already loaded; expansion is untouched.
  public var showHiddenFiles: Bool

  private var expanded: Set<URL>
  /// Loaded folder contents, unfiltered. Filled lazily by `children(of:)`, which
  /// the view calls while drawing, so the cache itself is not observed (a write
  /// there mid-draw would invalidate every row). A later change to an already
  /// loaded listing bumps `listingVersion` instead.
  @ObservationIgnored private var listings: [URL: [TreeNode]] = [:]
  private var listingVersion = 0
  @ObservationIgnored private let lister: DirectoryLister

  public convenience init(root: URL, options: FileTreeOptions = .init()) {
    self.init(root: root, options: options, lister: Directory.list)
  }

  init(root: URL, options: FileTreeOptions, lister: @escaping DirectoryLister) {
    self.root = URL(filePath: root.standardizedFileURL.path, directoryHint: .notDirectory)
    self.showHiddenFiles = options.showHiddenFiles
    self.lister = lister
    self.expanded = [self.root]
  }

  var rootNode: TreeNode {
    TreeNode(url: root, name: root.lastPathComponent, isDirectory: true, isSymlink: false)
  }

  /// The folder's entries, read from disk on the first call only. A folder
  /// that is never asked for is never read.
  public func children(of url: URL) -> [TreeNode] {
    _ = listingVersion
    let all = listings[url] ?? load(url)
    return showHiddenFiles ? all : all.filter { !$0.name.hasPrefix(".") }
  }

  public func isExpanded(_ url: URL) -> Bool { expanded.contains(url) }

  public func setExpanded(_ url: URL, _ isExpanded: Bool) {
    if isExpanded { expanded.insert(url) } else { expanded.remove(url) }
  }

  /// ponytail: an unreadable folder lists as empty. Surface it through onError
  /// if a host needs to tell "empty" from "permission denied".
  private func load(_ url: URL) -> [TreeNode] {
    let nodes = (try? lister(url)) ?? []
    listings[url] = nodes
    return nodes
  }
}
