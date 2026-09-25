import Foundation
import Observation
import SwiftUI

/// The tree's state: which folders are open, what they contain, and their
/// git status. `FileTreeView` draws it; hosts can also use it without the view.
@MainActor @Observable
public final class FileTree {
  public let root: URL
  public let options: FileTreeOptions
  /// Dot-named entries. Toggling re-filters what is already loaded; expansion is untouched.
  public var showHiddenFiles: Bool
  /// Light or dark rendering of the tree. Starts as `options.theme`; changing it
  /// re-themes in place, keeping open folders open.
  public var theme: ColorScheme
  /// The root folder was deleted or moved away while watched.
  public private(set) var rootMissing = false
  public private(set) var isPaused = false
  /// The highlighted row. A left click sets it; a host may also set or clear it,
  /// which calls no click handler and toggles no folder.
  public var selection: URL?
  /// The row the host is naming, drawn with `FileTreeView`'s `inlineEditor`. The
  /// tree only draws it; the host sets it, commits, and clears it.
  public var inlineEdit: InlineEdit?

  private var expanded: Set<URL>
  /// Loaded folder contents, unfiltered. Filled lazily by `children(of:)`, which
  /// the view calls while drawing, so the cache itself is not observed (a write
  /// there mid-draw would invalidate every row). A later change to an already
  /// loaded listing bumps `listingVersion` instead.
  @ObservationIgnored private var listings: [URL: [TreeNode]] = [:]
  private var listingVersion = 0
  @ObservationIgnored private let lister: DirectoryLister
  /// Nil when `useDevIcons` is off or the font is missing; rows then show `doc`.
  @ObservationIgnored let devIcons: DevIcons?
  @ObservationIgnored private let watcher: any FileWatching
  @ObservationIgnored private var treeWatch: WatchToken?
  /// FSEvents reports resolved paths (`/private/var/…`); the tree keeps the
  /// caller's spelling (`/var/…`). Nil when the two agree.
  @ObservationIgnored private let resolvedRoot: String?

  /// Last state the engine published. Rows read it; a click never waits on git.
  private var git = GitState()
  @ObservationIgnored private var engine: GitStatusEngine?
  /// The first full status load. Snapshots and first callbacks wait for it.
  @ObservationIgnored private(set) var started: Task<Void, Never>?
  @ObservationIgnored private var subscribers: [StatusSubscription: Subscriber] = [:]

  private struct Subscriber {
    let path: URL
    let callback: @MainActor ([URL: GitStatus]) -> Void
    /// False until the first full-map call has gone out, so no diff can precede it.
    var isReady = false
  }

  public convenience init(
    root: URL, options: FileTreeOptions = .init(), watcher: (any FileWatching)? = nil,
    onError: @escaping @MainActor (FileTreeError) -> Void = { _ in }
  ) {
    self.init(
      root: root, options: options, watcher: watcher ?? FSEventsWatcher(), lister: Directory.list,
      git: Git.run, devIcons: options.useDevIcons ? .shared : nil, onError: onError)
  }

  init(
    root: URL, options: FileTreeOptions, watcher: any FileWatching,
    lister: @escaping DirectoryLister, git run: @escaping GitRunner = Git.run,
    devIcons: DevIcons? = nil,
    onError: @escaping @MainActor (FileTreeError) -> Void = { _ in }
  ) {
    self.root = URL(filePath: root.standardizedFileURL.path, directoryHint: .notDirectory)
    self.options = options
    self.showHiddenFiles = options.showHiddenFiles
    self.theme = options.theme
    self.watcher = watcher
    self.lister = lister
    self.expanded = [self.root]
    if let devIcons, !devIcons.isAvailable { onError(.devIconsUnavailable) }
    self.devIcons = devIcons?.isAvailable == true ? devIcons : nil
    let resolved = Self.realPath(self.root.path)
    self.resolvedRoot = resolved == self.root.path ? nil : resolved
    startWatching()
    guard options.detectGit else { return }
    let engine = GitStatusEngine(
      treeRoot: self.root, options: options, run: run, watcher: watcher,
      publish: { [weak self] in self?.receive($0) },
      report: { onError($0) })
    self.engine = engine
    started = Task { await engine.start() }
  }

  var rootNode: TreeNode {
    TreeNode(url: root, name: root.lastPathComponent, isDirectory: true, isSymlink: false)
  }

  /// The folder's entries, read from disk on the first call only. A folder
  /// that is never asked for is never read. `.DS_Store` is never shown.
  public func children(of url: URL) -> [TreeNode] {
    _ = listingVersion
    let all = (listings[url] ?? load(url)).filter { $0.name != ".DS_Store" }
    return showHiddenFiles ? all : all.filter { !$0.name.hasPrefix(".") }
  }

  public func isExpanded(_ url: URL) -> Bool { expanded.contains(url) }

  /// The rows on screen, top to bottom: the root, then every expanded folder's
  /// children (filtered by `showHiddenFiles`), depth-first. Collapsed folders are never read.
  /// An `inlineEdit` creating in an open folder adds a new-entry row as its first child.
  func visibleRows() -> [VisibleRow] {
    var rows: [VisibleRow] = []
    func walk(_ node: TreeNode, depth: Int) {
      rows.append(VisibleRow(kind: .node(node), depth: depth))
      guard node.isDirectory, isExpanded(node.url) else { return }
      if case .create(let folder, let isDirectory) = inlineEdit, folder == node.url {
        rows.append(
          VisibleRow(kind: .newEntry(in: folder, isDirectory: isDirectory), depth: depth + 1))
      }
      for child in children(of: node.url) { walk(child, depth: depth + 1) }
    }
    walk(rootNode, depth: 0)
    return rows
  }

  public func setExpanded(_ url: URL, _ isExpanded: Bool) {
    if isExpanded { expanded.insert(url) } else { expanded.remove(url) }
  }

  // MARK: Git status

  /// Nil when the path isn't in a repo, or git is off or unavailable.
  public func status(of url: URL) -> GitStatus? {
    guard let repo = repoRoot(of: url) else { return nil }
    return StatusRollup.lookup(url, in: git.statuses, covering: git.covering, repoRoot: repo)
  }

  /// The branch (or short SHA when detached) of a repo-root folder, when `showBranchNames` is on.
  public func branch(of url: URL) -> String? {
    options.showBranchNames ? git.branches[url] : nil
  }

  /// The deepest repo holding `url`.
  func repoRoot(of url: URL) -> URL? {
    git.repoRoots.filter { $0.encloses(url) }.max { $0.path.count < $1.path.count }
  }

  /// Calls `callback` once with the status of every file and folder under
  /// `path`, then with only the entries that change.
  public func register(
    path: URL, callback: @escaping @MainActor ([URL: GitStatus]) -> Void
  ) throws -> StatusSubscription {
    let path = try validated(path)
    let subscription = StatusSubscription(id: UUID())
    subscribers[subscription] = Subscriber(path: path, callback: callback)
    Task {
      guard let initial = try? await snapshot(of: path), subscribers[subscription] != nil else {
        return
      }
      subscribers[subscription]?.isReady = true
      callback(initial)
    }
    return subscription
  }

  public func unregister(_ subscription: StatusSubscription) {
    subscribers[subscription] = nil
  }

  /// Every file and folder under `path` with its status, including tracked
  /// files deleted from disk. Runs `git ls-files`, so call it on demand.
  public func snapshot(of path: URL) async throws -> [URL: GitStatus] {
    let path = try validated(path)
    guard let engine else { throw FileTreeError.gitDetectionDisabled }
    await started?.value
    let tracked = await engine.trackedFiles(under: path)
    // Built from `git` as it is now, after the await, so a refresh that
    // landed meanwhile is included rather than lost.
    var result = git.statuses.filter { path.encloses($0.key) }
    for file in tracked {
      var url = file
      while path.encloses(url), result[url] == nil, let status = status(of: url) {
        result[url] = status
        url = url.parent
      }
    }
    return result
  }

  private func validated(_ path: URL) throws -> URL {
    guard engine != nil else { throw FileTreeError.gitDetectionDisabled }
    let path = URL(filePath: path.standardizedFileURL.path, directoryHint: .notDirectory)
    guard root.encloses(path) else { throw FileTreeError.pathOutsideRoot(path) }
    return path
  }

  private func receive(_ state: GitState) {
    let old = git.statuses
    git = state
    let changed = Set(old.keys).union(state.statuses.keys).filter { old[$0] != state.statuses[$0] }
    guard !changed.isEmpty else { return }
    for subscriber in subscribers.values where subscriber.isReady {
      var diff: [URL: GitStatus] = [:]
      for url in changed where subscriber.path.encloses(url) {
        if let status = state.statuses[url] {
          diff[url] = status
        } else if FileManager.default.fileExists(atPath: url.path), let status = status(of: url) {
          diff[url] = status  // dropped from the map: back to unmodified (or a covering status)
        }  // dropped and gone from disk: not reported
      }
      if !diff.isEmpty { subscriber.callback(diff) }
    }
  }

  // MARK: Clicks

  /// Selects the row; a folder also toggles open or closed.
  func select(_ node: TreeNode) {
    selection = node.url
    if node.isDirectory { setExpanded(node.url, !isExpanded(node.url)) }
  }

  /// From what's already loaded and the last published status, so a click never waits on git.
  public func info(for url: URL) -> TreeItemInfo {
    let node = url == root ? rootNode : listings[url.parent]?.first { $0.url == url }
    let repo = repoRoot(of: url)
    return TreeItemInfo(
      url: url,
      relativePath: String(url.path.dropFirst(root.path.count).drop { $0 == "/" }),
      isDirectory: node?.isDirectory ?? false,
      isSymlink: node?.isSymlink ?? false,
      repoRoot: repo,
      gitStatus: repo == nil ? nil : status(of: url))
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
    await engine?.refreshAll()
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
    let paths = batch.paths.compactMap(localized)
    if let engine { Task { await engine.filesChanged(paths) } }
    let changed = paths.filter { !$0.pathComponents.contains(".git") }
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
    listings = listings.filter { !folder.encloses($0.key) }
    expanded = expanded.filter { !folder.encloses($0) || $0 == root }
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
