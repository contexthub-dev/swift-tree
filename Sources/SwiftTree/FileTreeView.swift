import SwiftUI

/// A sidebar list of the tree, rooted at `tree.root`, which starts expanded.
public struct FileTreeView: View {
  let tree: FileTree

  public init(tree: FileTree) {
    self.tree = tree
  }

  public var body: some View {
    if tree.rootMissing {
      ContentUnavailableView(
        "Folder Missing", systemImage: "questionmark.folder",
        description: Text(tree.root.path))
    } else {
      List {
        FileTreeRow(node: tree.rootNode, tree: tree)
      }
      .listStyle(.sidebar)
    }
  }
}

private struct FileTreeRow: View {
  let node: TreeNode
  let tree: FileTree

  var body: some View {
    if node.isDirectory {
      DisclosureGroup(isExpanded: isExpanded) {
        // Guarded so a collapsed folder's children are never listed.
        if tree.isExpanded(node.url) {
          ForEach(tree.children(of: node.url)) { FileTreeRow(node: $0, tree: tree) }
        }
      } label: {
        label(
          icon: tree.isExpanded(node.url) ? "folder.fill" : "folder",
          branch: tree.branch(of: node.url))
      }
      .disclosureGroupStyle(PlainDisclosureStyle())
    } else {
      label(icon: node.isSymlink ? "link" : "doc")
    }
  }

  private var isExpanded: Binding<Bool> {
    Binding(get: { tree.isExpanded(node.url) }, set: { tree.setExpanded(node.url, $0) })
  }

  private func label(icon: String, branch: String? = nil) -> some View {
    Label {
      HStack(spacing: 6) {
        Text(node.name)
          .foregroundStyle(tree.status(of: node.url).flatMap(tree.options.colors.color) ?? .primary)
        if let branch {
          Text(branch).foregroundStyle(.secondary).font(.caption)
        }
      }
    } icon: {
      Image(systemName: icon)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}

/// A `DisclosureGroup` without a chevron, toggled by a click anywhere on its
/// label. SF Symbols has no open-folder glyph, so the filled folder icon marks
/// an open one. `Group` is transparent to `List`: label and children stay
/// separate rows, and the content's leading padding supplies the indent.
private struct PlainDisclosureStyle: DisclosureGroupStyle {
  static let indent: CGFloat = 12

  func makeBody(configuration: Configuration) -> some View {
    Group {
      configuration.label
        .onTapGesture { configuration.isExpanded.toggle() }
      if configuration.isExpanded {
        configuration.content
          .padding(.leading, Self.indent)
      }
    }
  }
}
