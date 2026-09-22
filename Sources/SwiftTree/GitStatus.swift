/// The git state of a file, or the rolled-up state of a folder.
public enum GitStatus: Sendable, Hashable {
  case unmodified, modified, untracked, staged, deleted, ignored
}
