import Foundation

@testable import SwiftTree

/// A fresh folder under the temp dir, removed on deinit.
final class TempDir {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.child("swift-tree-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: url) }

  /// Creates each path: a trailing "/" makes a folder, anything else an empty file.
  func make(_ paths: String...) throws {
    for path in paths {
      let target = url.child(path)
      if path.hasSuffix("/") {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      } else {
        try FileManager.default.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: target)
      }
    }
  }
}

/// A watcher the test drives by hand. Tracks every subscription separately.
final class FakeWatcher: FileWatching, @unchecked Sendable {
  private var subscriptions:
    [(id: UUID, paths: [URL], onChange: @Sendable (FileChangeBatch) -> Void)] = []

  var watched: [[URL]] { subscriptions.map(\.paths) }
  var active: Int { subscriptions.count }

  func watch(_ paths: [URL], onChange: @escaping @Sendable (FileChangeBatch) -> Void) -> WatchToken
  {
    let id = UUID()
    subscriptions.append((id, paths, onChange))
    return WatchToken { [weak self] in self?.subscriptions.removeAll { $0.id == id } }
  }

  /// Delivers to every subscription watching a path that encloses one in `batch`.
  func emit(_ batch: FileChangeBatch) {
    for sub in subscriptions
    where sub.paths.contains(where: { base in batch.paths.contains { base.encloses($0) } }) {
      sub.onChange(batch)
    }
  }
}

/// Runs git in `dir` with a fixed identity, failing the test on error.
@discardableResult
func git(_ args: String..., in dir: URL) throws -> String {
  let output = try Git.runBlocking(["-c", "user.name=t", "-c", "user.email=t@t"] + args, dir)
  return String(decoding: output, as: UTF8.self)
}

/// Polls `condition` on the main actor until it holds or `limit` passes.
@MainActor
func eventually(within limit: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
  let deadline = ContinuousClock.now + limit
  while ContinuousClock.now < deadline {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return condition()
}
