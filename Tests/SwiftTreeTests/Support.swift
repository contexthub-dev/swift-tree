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
