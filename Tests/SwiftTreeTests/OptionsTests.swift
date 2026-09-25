import SwiftUI
import Testing

@testable import SwiftTree

struct OptionsTests {
  @Test func defaultsShowGuidesAt12pt() {
    let options = FileTreeOptions()
    #expect(options.showIndentGuides)
    #expect(options.fontSize == 12)
    #expect(options.useDevIcons)
  }

  @Test func fontSizeIsClampedTo8Through32() {
    var options = FileTreeOptions()
    options.fontSize = 4
    #expect(options.fontSize == 8)
    options.fontSize = 60
    #expect(options.fontSize == 32)
    options.fontSize = 16
    #expect(options.fontSize == 16)
  }

  @Test func singleColorCoversChangesButKeepsIgnoredGray() {
    var colors = StatusColors(all: .orange)
    #expect(
      [colors.modified, colors.untracked, colors.staged, colors.deleted].allSatisfy {
        $0 == .orange
      })
    #expect(colors.ignored == StatusColors.zed.ignored)
    #expect(colors.color(for: .unmodified) == nil)
    colors.staged = .blue
    #expect(colors.staged == .blue && colors.modified == .orange)
  }

  @Test func fontFamilyDefaultsToTheSystemFont() {
    var options = FileTreeOptions()
    #expect(options.fontFamily == nil)
    #expect(options.font(size: 12) == .system(size: 12))
    options.fontFamily = "PT Sans"
    #expect(options.font(size: 12) == .custom("PT Sans", size: 12))
  }
}
