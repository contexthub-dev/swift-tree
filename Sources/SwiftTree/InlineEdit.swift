import Foundation

/// A row the host is naming in place: renaming an existing entry, or a new
/// entry about to be created as the first child of an open folder.
public enum InlineEdit: Equatable, Sendable {
  case rename(URL)
  case create(in: URL, isDirectory: Bool)
}
