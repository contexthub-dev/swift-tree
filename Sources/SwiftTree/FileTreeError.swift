import Foundation

public enum FileTreeError: Error, Equatable, Sendable {
  /// A status API path that isn't the root or beneath it.
  case pathOutsideRoot(URL)
  /// The status API was called with `detectGit = false`.
  case gitDetectionDisabled
  /// No usable `git` on PATH. Reported once; the tree shows no colors.
  case gitUnavailable
  /// One repo's git command failed. Reported once until it recovers; other repos are unaffected.
  case gitFailed(repo: URL, message: String)
  /// `useDevIcons` is on but the bundled devicon font is missing (no `make fonts`) or unreadable.
  /// Reported once, from `FileTree`'s init; file rows show `doc`.
  case devIconsUnavailable
}

/// Returned by `FileTree.register(path:callback:)`; pass to `unregister(_:)`.
public struct StatusSubscription: Hashable, Sendable {
  let id: UUID
}
