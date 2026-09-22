import Foundation
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

  @Test func otherChangesRebuildAndReleaseTheOldTree() throws {
    let model = DemoModel()
    model.open(root)
    weak var old = model.tree
    model.draft.modified = .purple
    model.draft.showHiddenFiles = false
    model.apply()
    #expect(model.tree != nil && model.tree !== old)
    #expect(old == nil)
    #expect(model.tree?.showHiddenFiles == false)
  }

  @Test func invalidLatencyBlocksApply() {
    let model = DemoModel()
    model.open(root)
    model.draft.latency = 10
    #expect(!model.canApply)
  }

  @Test func resetColorsRestoresZed() {
    var settings = DemoSettings()
    settings.deleted = .purple
    settings.resetColors()
    #expect(settings == DemoSettings())
  }
}
