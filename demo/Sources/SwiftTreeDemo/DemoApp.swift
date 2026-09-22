import AppKit
import SwiftTree
import SwiftUI

@main
struct DemoApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  @State private var model: DemoModel

  init() {
    let model = DemoModel()
    // `swift run --package-path demo SwiftTreeDemo -root <folder>` skips the picker. A bare
    // path argument would not work: AppKit takes it as a file to open and shows no window.
    if let path = UserDefaults.standard.string(forKey: "root") { model.open(URL(filePath: path)) }
    _model = State(initialValue: model)
  }

  var body: some Scene {
    WindowGroup("SwiftTree Demo") {
      ContentView(model: model)
    }
  }
}

/// `swift run` launches a bare executable: without this it gets no Dock icon and no focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
  }
}

@MainActor @Observable
final class DemoModel {
  private(set) var root: URL?
  private(set) var tree: FileTree?
  var draft = DemoSettings()
  private(set) var applied = DemoSettings()

  var canApply: Bool { tree != nil && draft != applied && draft.isLatencyValid }

  func open(_ url: URL) {
    root = url
    rebuild()
  }

  func apply() {
    guard canApply else { return }
    let hiddenOnly = draft.differsOnlyInHiddenFiles(from: applied)
    applied = draft
    if hiddenOnly {
      tree?.showHiddenFiles = applied.showHiddenFiles
    } else {
      rebuild()
    }
  }

  /// Replacing `tree` releases the old one, whose watch tokens cancel on deinit.
  private func rebuild() {
    guard let root else { return }
    tree = FileTree(
      root: root, options: applied.options, watcher: FSEventsWatcher(latency: applied.latency))
  }
}
