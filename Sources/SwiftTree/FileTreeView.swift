import SwiftUI

/// The tree rooted at `tree.root`, which starts expanded, as flat compact rows.
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
    content.environment(\.colorScheme, tree.options.theme)
  }

  /// A `LazyVStack`, not a `List`: the AppKit table under a macOS `List` adds row
  /// insets and a minimum height that break compact, gap-free rows.
  @ViewBuilder private var content: some View {
    if tree.rootMissing {
      ContentUnavailableView(
        "Folder Missing", systemImage: "questionmark.folder",
        description: Text(tree.root.path))
    } else {
      let metrics = RowMetrics(fontSize: tree.options.fontSize)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(tree.visibleRows()) { FileTreeRow(row: $0, metrics: metrics, view: self) }
        }
        .padding(.vertical, 4)
      }
      // Painted, so the chosen theme holds even when the host's appearance differs.
      .background(.background)
    }
  }
}

extension FileTreeView where RightClickMenu == EmptyView {
  public init(tree: FileTree, onLeftClick: @escaping @MainActor (TreeItemInfo) -> Void = { _ in }) {
    self.init(tree: tree, onLeftClick: onLeftClick) { _ in EmptyView() }
  }
}

/// A row on screen and how deep it sits; the root is depth 0.
struct VisibleRow: Identifiable, Equatable {
  let node: TreeNode
  let depth: Int
  var id: URL { node.url }
}

/// Row geometry from the font size. The ratios are tuned against Zed's look
/// (12pt → 20pt rows, 16pt indent); change them here, nowhere else.
struct RowMetrics: Equatable {
  let fontSize, rowHeight, indent, iconWidth, branchFontSize: CGFloat

  init(fontSize: CGFloat) {
    self.fontSize = fontSize
    rowHeight = (fontSize * 5 / 3).rounded()
    indent = (fontSize * 4 / 3).rounded()
    iconWidth = indent
    branchFontSize = (fontSize * 0.85).rounded()
  }
}

private struct FileTreeRow<RightClickMenu: View>: View {
  let row: VisibleRow
  let metrics: RowMetrics
  let view: FileTreeView<RightClickMenu>
  var tree: FileTree { view.tree }
  var node: TreeNode { row.node }

  var body: some View {
    HStack(spacing: 0) {
      Color.clear.frame(width: CGFloat(row.depth) * metrics.indent)
      Image(systemName: icon)
        .frame(width: metrics.iconWidth)
      Text(node.name)
        .foregroundStyle(tree.status(of: node.url).flatMap(tree.options.colors.color) ?? .primary)
        .padding(.leading, metrics.indent / 4)
      if let branch = tree.branch(of: node.url) {
        Text(branch)
          .font(.system(size: metrics.branchFontSize))
          .foregroundStyle(.secondary)
          .padding(.leading, metrics.indent / 2)
      }
      Spacer(minLength: 0)
    }
    .font(.system(size: metrics.fontSize))
    .lineLimit(1)
    .padding(.horizontal, metrics.indent / 2)
    .frame(height: metrics.rowHeight)
    .background(tree.selection == node.url ? Color.accentColor.opacity(0.18) : Color.clear)
    .contentShape(Rectangle())
    .onTapGesture {
      tree.select(node)
      view.onLeftClick(tree.info(for: node.url))
    }
    .contextMenu { view.rightClickMenu(tree.info(for: node.url)) }
  }

  /// SF Symbols has no open-folder glyph, so the filled folder marks an open one.
  private var icon: String {
    if node.isDirectory { return tree.isExpanded(node.url) ? "folder.fill" : "folder" }
    return node.isSymlink ? "link" : "doc"
  }
}
