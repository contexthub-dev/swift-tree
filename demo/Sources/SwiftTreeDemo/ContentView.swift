import SwiftTree
import SwiftUI

struct ContentView: View {
  @Bindable var model: DemoModel
  @State private var isPicking = false

  /// Standard macOS layout: navigator in the sidebar, settings in the content
  /// area (controls on the translucent sidebar lose their accent color), and
  /// details in the inspector.
  var body: some View {
    NavigationSplitView {
      Group {
        if let tree = model.tree {
          FileTreeView(tree: tree, onLeftClick: model.clicked) { item in
            Button("Reveal in Finder") {
              NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copy Relative Path") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(item.relativePath, forType: .string)
            }
          }
        } else {
          ContentUnavailableView {
            Label("No Folder", systemImage: "folder")
          } actions: {
            Button("Choose Folder…") { isPicking = true }
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 220, ideal: 280)
    } detail: {
      SettingsForm(model: model)
        .safeAreaInset(edge: .bottom) { FooterBar(model: model) }
        .inspector(isPresented: .constant(true)) {
          InspectorView(model: model).inspectorColumnWidth(min: 260, ideal: 300)
        }
    }
    .frame(minWidth: 900, minHeight: 500)
    // The tree themes itself; the rest of the window follows so the two match.
    .preferredColorScheme(model.applied.theme)
    .navigationTitle(model.root?.lastPathComponent ?? "SwiftTree Demo")
    .navigationSubtitle(model.root?.path ?? "")
    .toolbar {
      Button("Choose Folder…", systemImage: "folder") { isPicking = true }
      let isPaused = model.tree?.isPaused == true
      Button(
        isPaused ? "Resume Watching" : "Pause Watching",
        systemImage: isPaused ? "play.fill" : "pause.fill"
      ) {
        Task { await model.togglePause() }
      }
      .help(isPaused ? "Resume watching for file changes" : "Pause watching for file changes")
      .disabled(model.tree == nil)
    }
    .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { model.open(url) }
    }
  }
}

/// Watch state or the last error on the left, the default button on the right,
/// like a macOS sheet footer.
struct FooterBar: View {
  let model: DemoModel

  var body: some View {
    HStack {
      if let (error, at) = model.lastError {
        Label(
          "\(at.formatted(date: .omitted, time: .standard))  \(String(describing: error))",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.red)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(String(describing: error))
      } else if let tree = model.tree {
        Text(tree.isPaused ? "Watching paused" : "Watching for changes")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Apply") { model.apply() }
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canApply)
    }
    .padding(12)
    .background(.bar)
  }
}

struct InspectorView: View {
  let model: DemoModel

  var body: some View {
    Form {
      Section("Last clicked") {
        if let item = model.lastClicked {
          LabeledContent("Path", value: item.url.path)
          LabeledContent("Relative", value: item.relativePath)
          LabeledContent("Kind", value: item.isDirectory ? "Folder" : "File")
          LabeledContent("Symlink", value: item.isSymlink ? "Yes" : "No")
          LabeledContent("Repo root", value: item.repoRoot?.path ?? "none")
          LabeledContent("Git status", value: item.gitStatus.map { "\($0)" } ?? "none")
        } else {
          Text("Click a row").foregroundStyle(.secondary)
        }
      }
      Section("Status callbacks (\(model.log.count))") {
        ForEach(Array(model.log.enumerated().reversed()), id: \.offset) { Text($0.element) }
      }
    }
    .formStyle(.grouped)
    .textSelection(.enabled)
  }
}

struct SettingsForm: View {
  @Bindable var model: DemoModel

  var body: some View {
    Form {
      Section("Tree") {
        Toggle("Show hidden files", isOn: $model.draft.showHiddenFiles)
        Toggle("Detect git", isOn: $model.draft.detectGit)
        Toggle("Multiple git repositories", isOn: $model.draft.canHaveMultipleGitRepositories)
        Toggle("Show branch names", isOn: $model.draft.showBranchNames)
        Toggle(
          "Dark theme",
          isOn: Binding(
            get: { model.draft.theme == .dark },
            set: { model.draft.theme = $0 ? .dark : .light }))
        Toggle("Show indent guides", isOn: $model.draft.showIndentGuides)
        Stepper(
          "Font size: \(Int(model.draft.fontSize)) pt", value: $model.draft.fontSize, in: 8...32)
      }
      Section("Colors") {
        Toggle("Single color", isOn: $model.draft.useSingleColor)
        if model.draft.useSingleColor {
          ColorPicker("Changed files", selection: $model.draft.singleColor)
        } else {
          ColorPicker("Modified", selection: $model.draft.modified)
          ColorPicker("Untracked", selection: $model.draft.untracked)
          ColorPicker("Staged", selection: $model.draft.staged)
          ColorPicker("Deleted", selection: $model.draft.deleted)
          ColorPicker("Ignored", selection: $model.draft.ignored)
        }
        Button("Reset colors") { model.draft.resetColors() }
      }
      Section("Watcher") {
        TextField("Latency (s)", value: $model.draft.latency, format: .number)
        if !model.draft.isLatencyValid {
          Text("Latency must be 0.05–5.0 s").font(.caption).foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
  }
}
