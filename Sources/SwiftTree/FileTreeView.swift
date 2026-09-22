import SwiftUI

/// A sidebar list of the tree, rooted at `tree.root`, which starts expanded.
///
/// A left click selects the row (and toggles a folder), then calls `onLeftClick`.
/// A right click or control-click shows the menu `rightClickMenu` builds for
/// that row; an empty menu shows nothing.
public struct FileTreeView<RightClickMenu: View>: View {
  let tree: FileTree
  let onLeftClick: @MainActor (TreeItemInfo) -> Void
  let rightClickMenu: @MainActor (TreeItemInfo) -> RightClickMenu

  public init(
    tree: FileTree,
    onLeftClick: @escaping @MainActor (TreeItemInfo) -> Void = { _ in },
    @ViewBuilder rightClickMenu: @escaping @MainActor (TreeItemInfo) -> RightClickMenu
  ) {
    self.tree = tree
    self.onLeftClick = onLeftClick
    self.rightClickMenu = rightClickMenu
  }

  public var body: some View {
    if tree.rootMissing {
      ContentUnavailableView(
        "Folder Missing", systemImage: "questionmark.folder",
        description: Text(tree.root.path))
    } else {
      List {
        FileTreeRow(node: tree.rootNode, view: self)
      }
      .listStyle(.sidebar)
    }
  }
}

extension FileTreeView where RightClickMenu == EmptyView {
  public init(tree: FileTree, onLeftClick: @escaping @MainActor (TreeItemInfo) -> Void = { _ in }) {
    self.init(tree: tree, onLeftClick: onLeftClick) { _ in EmptyView() }
  }
}

private struct FileTreeRow<RightClickMenu: View>: View {
  let node: TreeNode
  let view: FileTreeView<RightClickMenu>
  var tree: FileTree { view.tree }

  var body: some View {
    if node.isDirectory {
      DisclosureGroup(isExpanded: isExpanded) {
        // Guarded so a collapsed folder's children are never listed.
        if tree.isExpanded(node.url) {
          ForEach(tree.children(of: node.url)) { FileTreeRow(node: $0, view: view) }
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

  /// The click targets sit on the label, not the DisclosureGroup: on the group
  /// they would also claim clicks on every child row.
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
    .onTapGesture {
      tree.select(node)
      view.onLeftClick(tree.info(for: node.url))
    }
    .contextMenu { view.rightClickMenu(tree.info(for: node.url)) }
    .listRowBackground(tree.selection == node.url ? Color.accentColor.opacity(0.18) : Color.clear)
  }
}

/// A `DisclosureGroup` without a chevron; the row's own tap toggles it. SF
/// Symbols has no open-folder glyph, so the filled folder icon marks an open
/// one. `Group` is transparent to `List`: label and children stay separate
/// rows, and the content's leading padding supplies the indent.
private struct PlainDisclosureStyle: DisclosureGroupStyle {
  static let indent: CGFloat = 12

  func makeBody(configuration: Configuration) -> some View {
    Group {
      configuration.label
      if configuration.isExpanded {
        configuration.content
          .padding(.leading, Self.indent)
      }
    }
  }
}
