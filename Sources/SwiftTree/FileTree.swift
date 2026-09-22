import Foundation
import Observation

/// The tree's state: which folders are open, what they contain, and (later)
/// their git status. `FileTreeView` draws it; hosts can also use it without the view.
@MainActor @Observable
public final class FileTree {
  public let root: URL
  /// Dot-named entries. Toggling re-filters what is already loaded; expansion is untouched.
  public var showHiddenFiles: Bool
  /// The root folder was deleted or moved away while watched.
  public private(set) var rootMissing = false
  public private(set) var isPaused = false

  private var expanded: Set<URL>
  /// Loaded folder contents, unfiltered. Filled lazily by `children(of:)`, which
  /// the view calls while drawing, so the cache itself is not observed (a write
  /// there mid-draw would invalidate every row). A later change to an already
  /// loaded listing bumps `listingVersion` instead.
  @ObservationIgnored private var listings: [URL: [TreeNode]] = [:]
  private var listingVersion = 0
  @ObservationIgnored private let lister: DirectoryLister
  @ObservationIgnored private let watcher: any FileWatching
  @ObservationIgnored private var treeWatch: WatchToken?
  /// FSEvents reports resolved paths (`/private/var/…`); the tree keeps the
  /// caller's spelling (`/var/…`). Nil when the two agree.
  @ObservationIgnored private let resolvedRoot: String?

  public convenience init(
    root: URL, options: FileTreeOptions = .init(), watcher: (any FileWatching)? = nil
  ) {
    self.init(
      root: root, options: options, watcher: watcher ?? FSEventsWatcher(), lister: Directory.list)
  }

  init(
    root: URL, options: FileTreeOptions, watcher: any FileWatching,
    lister: @escaping DirectoryLister
  ) {
    self.root = URL(filePath: root.standardizedFileURL.path, directoryHint: .notDirectory)
    self.showHiddenFiles = options.showHiddenFiles
    self.watcher = watcher
    self.lister = lister
    self.expanded = [self.root]
    let resolved = Self.realPath(self.root.path)
    self.resolvedRoot = resolved == self.root.path ? nil : resolved
    startWatching()
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

  // MARK: Watching

  /// Stop following file changes. Expansion is kept for `resume()`.
  public func pause() {
    treeWatch?.cancel()
    treeWatch = nil
    isPaused = true
  }

  /// Re-read the tree, drop open folders that vanished, keep the rest open, and watch again.
  public func resume() async {
    guard isPaused else { return }
    isPaused = false
    rootMissing = !FileManager.default.fileExists(atPath: root.path)
    expanded = expanded.filter { isFolder($0) }
    listings.removeAll()  // reloaded lazily by the view, open folders first
    listingVersion += 1
    startWatching()
  }

  private func startWatching() {
    treeWatch = watcher.watch([root]) { [weak self] batch in
      Task { @MainActor in self?.apply(batch) }
    }
  }

  /// Re-lists every loaded folder a batch touches: the changed path itself
  /// (coarse watchers report the folder) and its parent (FSEvents reports the entry).
  func apply(_ batch: FileChangeBatch) {
    guard !isPaused else { return }
    if batch.rootChanged {
      rootMissing = !FileManager.default.fileExists(atPath: root.path)
    }
    let changed = batch.paths.compactMap(localized).filter { !$0.pathComponents.contains(".git") }
    let folders = Set(changed + changed.map(\.parent)).filter { listings[$0] != nil }
    for folder in folders {
      if let nodes = try? lister(folder) {
        listings[folder] = nodes
      } else {
        forget(folder)
      }
    }
    if !folders.isEmpty { listingVersion += 1 }
  }

  /// Drops a vanished folder and everything cached beneath it, so a folder
  /// recreated under the same name starts collapsed and freshly read.
  private func forget(_ folder: URL) {
    let isGone = { (url: URL) in url == folder || url.path.hasPrefix(folder.path + "/") }
    listings = listings.filter { !isGone($0.key) }
    expanded = expanded.filter { !isGone($0) || $0 == root }
  }

  /// Maps an event path into the root's spelling; nil if it's outside the root.
  private func localized(_ url: URL) -> URL? {
    for base in [root.path, resolvedRoot].compactMap({ $0 }) {
      if url.path == base { return root }
      if url.path.hasPrefix(base + "/") { return root.child(url.path.dropFirst(base.count + 1)) }
    }
    return nil
  }

  private func isFolder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  /// ponytail: an unreadable folder lists as empty. Surface it through onError
  /// if a host needs to tell "empty" from "permission denied".
  private func load(_ url: URL) -> [TreeNode] {
    let nodes = (try? lister(url)) ?? []
    listings[url] = nodes
    return nodes
  }
}
