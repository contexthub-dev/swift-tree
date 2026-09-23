import Foundation
import Testing

@testable import SwiftTree

@MainActor
struct DevIconsTests {
  @Test func fullFileNameWinsOverExtension() {
    #expect(DevIcons.iconName(for: "Cargo.toml") == "rust")
    #expect(DevIcons.iconName(for: "Dockerfile") == "docker")
    #expect(DevIcons.iconName(for: ".gitignore") == "git")
  }

  @Test func extensionMatchIsCaseInsensitive() {
    #expect(DevIcons.iconName(for: "main.swift") == "swift")
    #expect(DevIcons.iconName(for: "SETUP.PY") == "python")
  }

  @Test func unmappedFilesHaveNoIcon() {
    #expect(DevIcons.iconName(for: "notes.xyz") == nil)
    #expect(DevIcons.iconName(for: "README") == nil)
  }

  @Test func missingFontMakesEveryLookupNil() throws {
    let dir = try TempDir()
    try Data(#"{"swift-plain":"ec34"}"#.utf8).write(to: dir.url.child("devicon-map.json"))

    let icons = DevIcons(directory: dir.url)

    #expect(!icons.isAvailable)
    #expect(icons.glyph(for: "main.swift") == nil)
    #expect(!DevIcons(directory: nil).isAvailable)
  }

  @Test(
    "the bundled font maps .swift to a glyph",
    .enabled(
      if: DevIcons.bundledDirectory.map {
        FileManager.default.fileExists(atPath: $0.child("devicon.ttf").path)
      } ?? false,
      "run `make fonts` first"))
  func bundledFontResolvesSwift() {
    let icons = DevIcons.shared

    #expect(icons.isAvailable)
    #expect(!icons.fontName.isEmpty)
    #expect(icons.glyph(for: "main.swift") != nil)
    #expect(icons.glyph(for: "notes.xyz") == nil)
  }

  @Test func missingFontIsReportedOnceAndRowsFallBack() throws {
    let dir = try TempDir()
    var options = FileTreeOptions()
    options.detectGit = false
    var errors: [FileTreeError] = []

    let tree = FileTree(
      root: dir.url, options: options, watcher: FakeWatcher(), lister: Directory.list,
      devIcons: DevIcons(directory: nil), onError: { errors.append($0) })

    #expect(errors == [.devIconsUnavailable])
    #expect(tree.devIcons == nil)
  }

  @Test func devIconsOffReportsNothing() throws {
    let dir = try TempDir()
    var options = FileTreeOptions()
    options.detectGit = false
    options.useDevIcons = false
    var errors: [FileTreeError] = []

    let tree = FileTree(root: dir.url, options: options, onError: { errors.append($0) })

    #expect(errors.isEmpty)
    #expect(tree.devIcons == nil)
  }
}
