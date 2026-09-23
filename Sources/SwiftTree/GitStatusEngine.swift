import Foundation

/// What the tree draws from: every non-unmodified path, rolled up to folders.
struct GitState: Sendable, Equatable {
  var statuses: [URL: GitStatus] = [:]
  /// Folders git reported whole ("! dir/", or an untracked nested repo when nesting is off).
  var covering: [URL: GitStatus] = [:]
  var repoRoots: Set<URL> = []
  /// Branch, or short SHA when detached, per repo root.
  var branches: [URL: String] = [:]
}

/// Finds repos, runs `git status` per repo, and publishes the merged state.
/// Each repo has its own git-dir watch, which stays on while the tree is paused.
actor GitStatusEngine {
  private struct Repo {
    var files: [URL: GitStatus] = [:]
    var covering: [URL: GitStatus] = [:]
    var branch: String?
    var failing = false
    var watch: WatchToken?
  }

  private let treeRoot: URL
  private let nested: Bool
  private let run: GitRunner
  private let watcher: any FileWatching
  private let publish: @MainActor @Sendable (GitState) -> Void
  private let report: @MainActor @Sendable (FileTreeError) -> Void
  private var repos: [URL: Repo] = [:]
  private var refreshing: Set<URL> = []
  private var queued: Set<URL> = []
  /// No usable git. Reported once; nothing runs again until `refreshAll()` (resume).
  private var unavailable = false

  init(
    treeRoot: URL, options: FileTreeOptions, run: @escaping GitRunner,
    watcher: any FileWatching,
    publish: @escaping @MainActor @Sendable (GitState) -> Void,
    report: @escaping @MainActor @Sendable (FileTreeError) -> Void
  ) {
    self.treeRoot = treeRoot
    self.nested = options.canHaveMultipleGitRepositories
    self.run = run
    self.watcher = watcher
    self.publish = publish
    self.report = report
  }

  /// Finds the repo containing the tree root and loads it, nested repos included.
  /// Not a repo → nothing to color.
  func start() async {
    guard (try? await run(["--version"], URL(filePath: "/"))) != nil else {
      unavailable = true
      await report(.gitUnavailable)
      return
    }
    unavailable = false
    guard let top = await discover(treeRoot) else { return }
    await refresh(top)
  }

  /// Also retries git from scratch if it was unavailable.
  func refreshAll() async {
    if unavailable { return await start() }
    for root in repos.keys { await refresh(root) }
  }

  /// Tree-watch paths. Each refreshes the deepest repo holding it. A known
  /// repo's own `.git` is skipped (its git-dir watch covers that); any other
  /// `.git` — a `git init` in a subfolder — refreshes the repo around it,
  /// whose status then reveals the new repo.
  func filesChanged(_ paths: [URL]) async {
    var dirty: Set<URL> = []
    for path in paths {
      guard let root = deepestRepo(holding: path), !root.child(".git").encloses(path) else {
        continue
      }
      dirty.insert(root)
    }
    for root in dirty { await refresh(root) }
  }

  /// Tracked files under `path`, for snapshots. Runs only on demand.
  func trackedFiles(under path: URL) async -> [URL] {
    var files: [URL] = []
    for root in repos.keys where root.encloses(path) || path.encloses(root) {
      guard let output = try? await run(["ls-files", "-z"], root) else { continue }
      files += output.split(separator: 0)
        .map { root.child(String(decoding: $0, as: UTF8.self)) }
        .filter { path.encloses($0) }
    }
    return files
  }

  // MARK: Refresh

  /// One refresh per repo in flight; asking again meanwhile queues exactly one more.
  func refresh(_ root: URL) async {
    // A deleted root is shown as missing; its repos would only fail.
    guard repos[root] != nil, !unavailable,
      FileManager.default.fileExists(atPath: treeRoot.path)
    else { return }
    guard refreshing.insert(root).inserted else {
      queued.insert(root)
      return
    }
    repeat { await load(root) } while queued.remove(root) != nil
    refreshing.remove(root)
    await publish(merged())
  }

  private func load(_ root: URL) async {
    let status: PorcelainStatus
    let submodules: [String]
    do {
      status = StatusParser.parse(
        try await run(
          [
            "--no-optional-locks", "status", "--porcelain=v2", "-z", "--branch",
            "--untracked-files=all", "--ignored=matching",
          ], root))
      submodules = nested ? await submodulePaths(root) : []
    } catch {
      guard repos[root] != nil else { return }
      repos[root]?.files = [:]
      repos[root]?.covering = [:]
      repos[root]?.branch = nil
      if repos[root]?.failing == false {
        repos[root]?.failing = true
        await report(.gitFailed(repo: root, message: "\(error)"))
      }
      return
    }

    var entries = status.entries
    if nested {
      // A clean submodule never shows up in status, so `.gitmodules` is asked too.
      for path in status.nestedRepoCandidates + submodules {
        let dir = root.child(path.trimmingSuffix("/"))
        guard treeRoot.encloses(dir), hasGit(dir) else { continue }
        if repos[dir] == nil {
          // A broken `.git` resolves to the repo around it: leave the folder as git reports it.
          guard await discover(dir) == dir else { continue }
          await refresh(dir)
        }
        entries[path] = nil
      }
      dropVanishedRepos(under: root)
    }

    var files: [URL: GitStatus] = [:]
    var covering: [URL: GitStatus] = [:]
    for (path, value) in entries {
      let url = root.child(path.trimmingSuffix("/"))
      guard treeRoot.encloses(url) || url.encloses(treeRoot) else { continue }
      files[url] = value
      if path.hasSuffix("/") { covering[url] = value }
    }
    repos[root]?.files = files
    repos[root]?.covering = covering
    repos[root]?.branch = status.branch ?? status.oid.map { String($0.prefix(7)) }
    repos[root]?.failing = false
  }

  /// Registers the repo at or above `dir` and starts its git-dir watch.
  /// Returns its root in the tree's spelling, or nil if `dir` isn't in a repo.
  private func discover(_ dir: URL) async -> URL? {
    guard
      let output = try? await run(
        ["rev-parse", "--show-prefix", "--absolute-git-dir", "--git-common-dir"], dir)
    else { return nil }
    let lines = String(decoding: output, as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count >= 3 else { return nil }
    // git answers with resolved paths; walk up from `dir` instead to keep the tree's spelling.
    var root = dir
    for _ in lines[0].split(separator: "/") { root = root.parent }
    guard repos[root] == nil else { return root }

    // The common dir differs from the git dir in worktrees, and may be relative to `dir`.
    let gitDirs = Set(
      lines[1...2].map { line in
        line.hasPrefix("/")
          ? URL(filePath: String(line)) : dir.appending(path: String(line)).standardizedFileURL
      })
    let found = root
    var repo = Repo()
    repo.watch = watcher.watch(Array(gitDirs)) { [weak self] _ in
      Task { await self?.refresh(found) }
    }
    repos[found] = repo
    return found
  }

  private func submodulePaths(_ root: URL) async -> [String] {
    guard FileManager.default.fileExists(atPath: root.child(".gitmodules").path) else { return [] }
    // `-z` records are "key\nvalue\0". Exit 1 means no matches.
    let output =
      (try? await run(
        ["config", "-z", "--file", ".gitmodules", "--get-regexp", #"^submodule\..*\.path$"#], root))
      ?? Data()
    return output.split(separator: 0).compactMap {
      String(decoding: $0, as: UTF8.self).split(separator: "\n", maxSplits: 1).last.map(String.init)
    }
  }

  /// A nested repo whose `.git` was removed now belongs to the repo around it.
  private func dropVanishedRepos(under root: URL) {
    for other in repos.keys where other != root && root.encloses(other) && !hasGit(other) {
      repos[other]?.watch?.cancel()
      repos[other] = nil
    }
  }

  private func deepestRepo(holding path: URL) -> URL? {
    repos.keys.filter { $0.encloses(path) }.max { $0.path.count < $1.path.count }
  }

  private func hasGit(_ dir: URL) -> Bool {
    FileManager.default.fileExists(atPath: dir.child(".git").path)
  }

  private func merged() -> GitState {
    var state = GitState(repoRoots: Set(repos.keys))
    var files: [URL: GitStatus] = [:]
    for (root, repo) in repos {
      files.merge(repo.files) { own, _ in own }
      state.covering.merge(repo.covering) { own, _ in own }
      state.branches[root] = repo.branch
    }
    // Roll up across nested repos too, so an outer folder reflects everything inside it.
    if let top = repos.keys.min(by: { $0.path.count < $1.path.count }) {
      state.statuses = StatusRollup.rollUp(files, repoRoot: top)
    }
    return state
  }
}

extension String {
  func trimmingSuffix(_ suffix: String) -> String {
    hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
  }
}
