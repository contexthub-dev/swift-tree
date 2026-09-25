import SwiftUI

/// The tree rooted at `tree.root`, which starts expanded, as flat compact rows.
///
/// A left click selects the row (and toggles a folder), then calls `onLeftClick`.
/// A right click or control-click shows the menu `rightClickMenu` builds for
/// that row; an empty menu shows nothing.
///
/// While `tree.inlineEdit` is set, `inlineEditor` draws in place of the row's
/// name (rename) or as a new first row inside the folder (create), keeping the
/// row's icon, indent and guides.
public struct FileTreeView<RightClickMenu: View, InlineEditor: View>: View {
  let tree: FileTree
  let onLeftClick: @MainActor (TreeItemInfo) -> Void
  let rightClickMenu: @MainActor (TreeItemInfo) -> RightClickMenu
  let inlineEditor: @MainActor (InlineEdit) -> InlineEditor

  public init(
    tree: FileTree,
    onLeftClick: @escaping @MainActor (TreeItemInfo) -> Void = { _ in },
    @ViewBuilder rightClickMenu: @escaping @MainActor (TreeItemInfo) -> RightClickMenu,
    @ViewBuilder inlineEditor: @escaping @MainActor (InlineEdit) -> InlineEditor
  ) {
    self.tree = tree
    self.onLeftClick = onLeftClick
    self.rightClickMenu = rightClickMenu
    self.inlineEditor = inlineEditor
  }

  public var body: some View {
    content.environment(\.colorScheme, tree.theme)
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
          ForEach(tree.visibleRows()) { row in
            switch row.kind {
            case .node(let node):
              FileTreeRow(node: node, depth: row.depth, metrics: metrics, view: self)
            case .newEntry(let folder, let isDirectory):
              RowLayout(depth: row.depth, metrics: metrics, tree: tree) {
                Image(systemName: isDirectory ? "folder" : "doc")
              } name: {
                inlineEditor(.create(in: folder, isDirectory: isDirectory))
              }
            }
          }
        }
        .padding(.vertical, 4)
      }
      // Painted, so the chosen theme holds even when the host's appearance differs.
      .background(.background)
    }
  }
}

extension FileTreeView where InlineEditor == EmptyView {
  public init(
    tree: FileTree,
    onLeftClick: @escaping @MainActor (TreeItemInfo) -> Void = { _ in },
    @ViewBuilder rightClickMenu: @escaping @MainActor (TreeItemInfo) -> RightClickMenu
  ) {
    self.init(tree: tree, onLeftClick: onLeftClick, rightClickMenu: rightClickMenu) { _ in
      EmptyView()
    }
  }
}

extension FileTreeView where RightClickMenu == EmptyView, InlineEditor == EmptyView {
  public init(tree: FileTree, onLeftClick: @escaping @MainActor (TreeItemInfo) -> Void = { _ in }) {
    self.init(tree: tree, onLeftClick: onLeftClick) { _ in EmptyView() }
  }
}

/// A row on screen and how deep it sits; the root is depth 0.
struct VisibleRow: Identifiable, Equatable {
  /// A listed entry, or the host's new-entry row as the first child of `in`.
  enum Kind: Hashable {
    case node(TreeNode)
    case newEntry(in: URL, isDirectory: Bool)
  }
  let kind: Kind
  let depth: Int
  var id: Kind { kind }
  var node: TreeNode? {
    if case .node(let node) = kind { node } else { nil }
  }
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

/// Guides, icon and name at a row's depth: what every row, including the
/// new-entry row, shares. The font family and size apply to the whole row.
private struct RowLayout<Icon: View, Name: View>: View {
  let depth: Int
  let metrics: RowMetrics
  let tree: FileTree
  @ViewBuilder let icon: Icon
  @ViewBuilder let name: Name

  var body: some View {
    HStack(spacing: 0) {
      IndentGuides(depth: depth, metrics: metrics, isVisible: tree.options.showIndentGuides)
      icon
        .frame(width: metrics.iconWidth)
      name
        .padding(.leading, metrics.indent / 4)
      Spacer(minLength: 0)
    }
    .font(tree.options.font(size: metrics.fontSize))
    .lineLimit(1)
    .padding(.horizontal, metrics.indent / 2)
    .frame(height: metrics.rowHeight)
  }
}

private struct FileTreeRow<RightClickMenu: View, InlineEditor: View>: View {
  let node: TreeNode
  let depth: Int
  let metrics: RowMetrics
  let view: FileTreeView<RightClickMenu, InlineEditor>
  var tree: FileTree { view.tree }

  var body: some View {
    RowLayout(depth: depth, metrics: metrics, tree: tree) {
      icon
    } name: {
      if tree.inlineEdit == .rename(node.url) {
        view.inlineEditor(.rename(node.url))
      } else {
        HStack(spacing: 0) {
          Text(node.name)
            .foregroundStyle(
              tree.status(of: node.url).flatMap(tree.options.colors.color) ?? .primary)
          if let branch = tree.branch(of: node.url) {
            Text(branch)
              .font(tree.options.font(size: metrics.branchFontSize))
              .foregroundStyle(.secondary)
              .padding(.leading, metrics.indent / 2)
          }
        }
      }
    }
    .background(tree.selection == node.url ? Color.accentColor.opacity(0.18) : Color.clear)
    .contentShape(Rectangle())
    .onTapGesture {
      // A click into the host's rename field is the field's, not the row's.
      guard tree.inlineEdit != .rename(node.url) else { return }
      tree.select(node)
      view.onLeftClick(tree.info(for: node.url))
    }
    .contextMenu { view.rightClickMenu(tree.info(for: node.url)) }
  }

  /// A devicon glyph for a mapped file, otherwise an SF Symbol. SF Symbols has
  /// no open-folder glyph, so the filled folder marks an open one.
  @ViewBuilder private var icon: some View {
    if node.isDirectory {
      Image(systemName: tree.isExpanded(node.url) ? "folder.fill" : "folder")
    } else if node.isSymlink {
      Image(systemName: "link")
    } else if let devIcons = tree.devIcons, let glyph = devIcons.glyph(for: node.name) {
      Text(String(glyph)).font(.custom(devIcons.fontName, size: metrics.fontSize))
    } else {
      Image(systemName: "doc")
    }
  }
}

extension FileTreeOptions {
  /// `fontFamily` at `size`, or the system font when unset.
  func font(size: CGFloat) -> Font {
    fontFamily.map { .custom($0, size: size) } ?? .system(size: size)
  }
}

/// One 1pt line per ancestor level, centered under that ancestor's icon. Each
/// segment fills the full row height, so the rows' segments join into one line
/// that ends at the folder's last visible descendant. Invisible guides still
/// take their width, so turning them off never shifts the layout.
private struct IndentGuides: View {
  let depth: Int
  let metrics: RowMetrics
  let isVisible: Bool

  var body: some View {
    Canvas { context, size in
      guard isVisible else { return }
      for level in 0..<depth {
        let x = CGFloat(level) * metrics.indent + metrics.iconWidth / 2
        context.fill(
          Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)),
          with: .color(.primary.opacity(0.15)))
      }
    }
    .frame(width: CGFloat(depth) * metrics.indent)
  }
}
