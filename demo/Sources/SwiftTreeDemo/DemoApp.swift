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
  private(set) var lastClicked: TreeItemInfo?
  private(set) var lastError: (error: FileTreeError, at: Date)?
  /// One line per status callback, newest last.
  private(set) var log: [String] = []
  private var subscription: StatusSubscription?

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

  func togglePause() async {
    guard let tree else { return }
    if tree.isPaused { await tree.resume() } else { tree.pause() }
  }

  func clicked(_ item: TreeItemInfo) { lastClicked = item }

  func append(_ line: String) {
    log.append(line)
    log.removeFirst(max(0, log.count - 200))
  }

  /// Replacing `tree` releases the old one, whose watch tokens cancel on deinit.
  private func rebuild() {
    guard let root else { return }
    if let subscription { tree?.unregister(subscription) }
    (subscription, lastClicked, lastError, log) = (nil, nil, nil, [])
    let tree = FileTree(
      root: root, options: applied.options, watcher: FSEventsWatcher(latency: applied.latency),
      onError: { [weak self] in self?.lastError = ($0, .now) })
    self.tree = tree
    // With git off, register succeeds but never calls back.
    guard applied.detectGit else { return }
    subscription = try? tree.register(path: tree.root) { [weak self] statuses in
      let time = Date.now.formatted(date: .omitted, time: .standard)
      self?.append("\(time)  \(statuses.count) entries")
    }
  }
}
