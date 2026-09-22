import SwiftTree
import SwiftUI

struct ContentView: View {
  let model: DemoModel
  @State private var isPicking = false

  var body: some View {
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
    .frame(minWidth: 400, minHeight: 400)
    .navigationTitle(model.root?.path ?? "SwiftTree Demo")
    .toolbar {
      Button("Choose Folder…", systemImage: "folder") { isPicking = true }
    }
    .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { model.open(url) }
    }
  }
}
