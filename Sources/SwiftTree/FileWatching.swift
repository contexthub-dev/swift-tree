import CoreServices
import Foundation
import os

/// Something that reports batched file changes under a set of paths. Pass one
/// to `FileTree` to share a single watcher across your app.
public protocol FileWatching: AnyObject, Sendable {
  /// Calls `onChange` with batched events under any of `paths` until the token is cancelled.
  func watch(_ paths: [URL], onChange: @escaping @Sendable (FileChangeBatch) -> Void) -> WatchToken
}

public struct FileChangeBatch: Sendable {
  /// Changed files and folders. Either spelling of a symlinked root (e.g. `/var` or `/private/var`) works.
  public let paths: [URL]
  /// A watched path itself was deleted, moved, or recreated.
  public let rootChanged: Bool

  public init(paths: [URL], rootChanged: Bool = false) {
    self.paths = paths
    self.rootChanged = rootChanged
  }
}

/// Ends one `watch` subscription. Cancelling twice is harmless, and dropping
/// the last reference cancels too.
public final class WatchToken: Sendable {
  private let onCancel: OSAllocatedUnfairLock<(@Sendable () -> Void)?>

  public init(onCancel: @escaping @Sendable () -> Void) {
    self.onCancel = OSAllocatedUnfairLock(initialState: onCancel)
  }

  public func cancel() {
    onCancel.withLock { cancel in
      defer { cancel = nil }
      return cancel
    }?()
  }

  deinit { cancel() }
}

/// The built-in watcher: one FSEvents stream per `watch` call. The latency
/// window is what batches a burst (a checkout, an `npm install`) into one event.
public final class FSEventsWatcher: FileWatching {
  private let latency: TimeInterval

  public init(latency: TimeInterval = 0.3) {
    self.latency = latency
  }

  public func watch(_ paths: [URL], onChange: @escaping @Sendable (FileChangeBatch) -> Void)
    -> WatchToken
  {
    let handler = Handler(onChange)
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
      retain: nil, release: nil, copyDescription: nil)
    let flags = FSEventStreamCreateFlags(
      kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        | kFSEventStreamCreateFlagUseCFTypes)
    guard
      let stream = FSEventStreamCreate(
        nil, Handler.callback, &context, paths.map(\.path) as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
    else { return WatchToken {} }

    let queue = DispatchQueue(label: "swift-tree.fsevents")
    FSEventStreamSetDispatchQueue(stream, queue)
    FSEventStreamStart(stream)
    // The token owns the stream and keeps `handler` alive until it's torn down.
    nonisolated(unsafe) let owned = stream
    return WatchToken {
      FSEventStreamStop(owned)
      FSEventStreamInvalidate(owned)
      FSEventStreamRelease(owned)
      withExtendedLifetime(handler) {}
    }
  }

  private final class Handler: Sendable {
    let onChange: @Sendable (FileChangeBatch) -> Void
    init(_ onChange: @escaping @Sendable (FileChangeBatch) -> Void) { self.onChange = onChange }

    static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
      guard let info else { return }
      let handler = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue()
      let urls = (unsafeBitCast(paths, to: NSArray.self) as? [String] ?? [])
        .map { URL(filePath: $0, directoryHint: .notDirectory) }
      let rootChanged = (0..<count).contains {
        flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
      }
      handler.onChange(FileChangeBatch(paths: urls, rootChanged: rootChanged))
    }
  }
}
