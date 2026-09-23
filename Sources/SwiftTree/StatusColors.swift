import AppKit
import SwiftUI

/// Row text color per git status. Unmodified rows keep the normal text color.
public struct StatusColors: Sendable {
  public var modified, untracked, staged, deleted, ignored: Color

  public init(modified: Color, untracked: Color, staged: Color, deleted: Color, ignored: Color) {
    self.modified = modified
    self.untracked = untracked
    self.staged = staged
    self.deleted = deleted
    self.ignored = ignored
  }

  /// One color for modified, untracked, staged and deleted. Ignored keeps Zed's gray;
  /// set any status afterwards to override just that one.
  public init(all color: Color) {
    self.init(
      modified: color, untracked: color, staged: color, deleted: color,
      ignored: StatusColors.zed.ignored)
  }

  /// Zed's One Dark / One Light status colors (`modified`, `created`, `deleted`,
  /// `ignored`), switching with the system appearance. Zed has no staged
  /// color, so staged borrows its `renamed` blue (a rename reads as staged here too).
  public static let zed = StatusColors(
    modified: .adaptive(light: 0xa48819, dark: 0xdec184),
    untracked: .adaptive(light: 0x669f59, dark: 0xa1c181),
    staged: .adaptive(light: 0x5c78e2, dark: 0x74ade8),
    deleted: .adaptive(light: 0xd36151, dark: 0xd07277),
    ignored: .adaptive(light: 0x7e8086, dark: 0x878a98))

  public func color(for status: GitStatus) -> Color? {
    switch status {
    case .unmodified: nil
    case .modified: modified
    case .untracked: untracked
    case .staged: staged
    case .deleted: deleted
    case .ignored: ignored
    }
  }
}

extension Color {
  fileprivate static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let rgb = isDark ? dark : light
        return NSColor(
          srgbRed: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255,
          blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
      })
  }
}
