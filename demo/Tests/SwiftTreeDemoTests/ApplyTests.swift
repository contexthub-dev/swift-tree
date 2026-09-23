import Foundation
import SwiftTree
import SwiftUI
import Testing

@testable import SwiftTreeDemo

@MainActor struct ApplyTests {
  let root = FileManager.default.temporaryDirectory

  @Test func hiddenFilesAloneTogglesTheLiveTree() throws {
    let model = DemoModel()
    model.open(root)
    let tree = try #require(model.tree)
    model.draft.showHiddenFiles = false
    model.apply()
    #expect(model.tree === tree)
    #expect(tree.showHiddenFiles == false)
    #expect(!model.canApply)
  }

  @Test func otherChangesRebuildAndReleaseTheOldTree() async throws {
    let model = DemoModel()
    model.open(root)
    weak let old = model.tree
    model.draft.modified = .purple
    model.draft.showHiddenFiles = false
    model.apply()
    #expect(model.tree != nil && model.tree !== old)
    // register's first-snapshot Task holds the old tree briefly; it must still go away.
    for _ in 0..<100 where old != nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(old == nil)
    #expect(model.tree?.showHiddenFiles == false)
  }

  @Test func invalidLatencyBlocksApply() {
    let model = DemoModel()
    model.open(root)
    model.draft.latency = 10
    #expect(!model.canApply)
  }

  @Test func devIconsToggleRebuildsWithIt() throws {
    let model = DemoModel()
    model.open(root)
    let tree = try #require(model.tree)
    #expect(tree.options.useDevIcons)

    model.draft.useDevIcons = false
    model.apply()

    #expect(model.tree !== tree)
    #expect(model.tree?.options.useDevIcons == false)
  }

  @Test func resetColorsRestoresZed() {
    var settings = DemoSettings()
    settings.deleted = .purple
    settings.resetColors()
    #expect(settings == DemoSettings())
  }
}

@MainActor struct PauseTests {
  @Test func togglePauseFlipsTheTree() async throws {
    let model = DemoModel()
    model.open(FileManager.default.temporaryDirectory)
    let tree = try #require(model.tree)
    await model.togglePause()
    #expect(tree.isPaused)
    await model.togglePause()
    #expect(!tree.isPaused)
  }
}

@MainActor struct LogTests {
  @Test func logKeepsTheNewest200Lines() {
    let model = DemoModel()
    for i in 0..<250 { model.append("\(i)") }
    #expect(model.log.count == 200)
    #expect(model.log.first == "50" && model.log.last == "249")
  }

  @Test func rebuildClearsTheLog() {
    let model = DemoModel()
    model.open(FileManager.default.temporaryDirectory)
    model.append("old")
    model.draft.showBranchNames = true
    model.apply()
    #expect(model.log.isEmpty)
  }
}

@MainActor struct NewOptionsTests {
  @Test func singleColorMapsToEveryChangeButIgnored() {
    var settings = DemoSettings()
    settings.useSingleColor = true
    settings.singleColor = .purple
    let colors = settings.options.colors
    #expect(
      [colors.modified, colors.untracked, colors.staged, colors.deleted].allSatisfy {
        $0 == .purple
      })
    #expect(colors.ignored == StatusColors.zed.ignored)
  }

  @Test func guidesAndFontSizeRebuildTheTree() throws {
    let model = DemoModel()
    model.open(FileManager.default.temporaryDirectory)
    let old = try #require(model.tree)
    model.draft.showIndentGuides = false
    model.draft.fontSize = 16
    model.apply()
    let tree = try #require(model.tree)
    #expect(tree !== old)
    #expect(!tree.options.showIndentGuides && tree.options.fontSize == 16)
  }

  @Test func resetColorsTurnsSingleColorOff() {
    var settings = DemoSettings()
    settings.useSingleColor = true
    settings.singleColor = .purple
    settings.resetColors()
    #expect(settings == DemoSettings())
  }
}
