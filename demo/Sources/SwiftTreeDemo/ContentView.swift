import SwiftTree
import SwiftUI

struct ContentView: View {
  @Bindable var model: DemoModel
  @State private var isPicking = false

  var body: some View {
    NavigationSplitView {
      SettingsForm(model: model)
        .navigationSplitViewColumnWidth(min: 240, ideal: 260)
    } detail: {
      Group {
        if let tree = model.tree {
          FileTreeView(tree: tree)
        } else {
          ContentUnavailableView {
            Label("No Folder", systemImage: "folder")
          } actions: {
            Button("Choose Folder…") { isPicking = true }
          }
        }
      }
      .safeAreaInset(edge: .bottom) { StatusBar(model: model) }
    }
    .frame(minWidth: 700, minHeight: 450)
    .navigationTitle(model.root?.path ?? "SwiftTree Demo")
    .toolbar {
      Button("Choose Folder…", systemImage: "folder") { isPicking = true }
    }
    .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { model.open(url) }
    }
  }
}

struct StatusBar: View {
  let model: DemoModel

  var body: some View {
    HStack {
      let isPaused = model.tree?.isPaused == true
      Button(isPaused ? "Resume watching" : "Pause watching") {
        Task { await model.togglePause() }
      }
      .disabled(model.tree == nil)
      Spacer()
    }
    .padding(8)
    .background(.bar)
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
      }
      Section("Colors") {
        ColorPicker("Modified", selection: $model.draft.modified)
        ColorPicker("Untracked", selection: $model.draft.untracked)
        ColorPicker("Staged", selection: $model.draft.staged)
        ColorPicker("Deleted", selection: $model.draft.deleted)
        ColorPicker("Ignored", selection: $model.draft.ignored)
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
    // Pinned below the form so it never scrolls out of reach.
    .safeAreaInset(edge: .bottom) {
      Button("Apply") { model.apply() }
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canApply)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
  }
}
