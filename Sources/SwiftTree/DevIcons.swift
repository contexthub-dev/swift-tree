import CoreText
import Foundation

/// The bundled devicon font and its glyph map, loaded once per process.
///
/// Both come from `make fonts` (release tags carry them). When they're missing,
/// `isAvailable` is false and file rows keep the `doc` symbol.
@MainActor
final class DevIcons {
  static let shared = DevIcons(directory: bundledDirectory)
  /// The package's `DevIcons` resource folder (it always exists; its files may not).
  nonisolated static let bundledDirectory = Bundle.module.url(
    forResource: "DevIcons", withExtension: nil)

  /// Font and map both loaded; false means every lookup returns nil.
  let isAvailable: Bool
  /// The registered font's PostScript name, for `Font.custom`.
  let fontName: String
  private let glyphs: [String: Character]

  /// `directory` holds `devicon.ttf` and `devicon-map.json`; tests pass their own.
  init(directory: URL?) {
    guard let directory,
      let data = try? Data(contentsOf: directory.child("devicon-map.json")),
      let codes = try? JSONDecoder().decode([String: String].self, from: data),
      let fontName = Self.register(directory.child("devicon.ttf"))
    else {
      (isAvailable, fontName, glyphs) = (false, "", [:])
      return
    }
    self.fontName = fontName
    glyphs = codes.compactMapValues { code in
      UInt32(code, radix: 16).flatMap(Unicode.Scalar.init).map(Character.init)
    }
    isAvailable = !glyphs.isEmpty
  }

  /// The glyph for a file, or nil when unmapped or the font is missing.
  func glyph(for fileName: String) -> Character? {
    guard isAvailable, let name = Self.iconName(for: fileName) else { return nil }
    return glyphs[name + "-plain"] ?? glyphs[name + "-original"]
  }

  /// The devicon name for a file: its full name first (`Dockerfile`), then its
  /// extension, both case-insensitive.
  static func iconName(for fileName: String) -> String? {
    let name = fileName.lowercased()
    if let icon = table[name] { return icon }
    let ext = (name as NSString).pathExtension
    return ext.isEmpty ? nil : table[ext]
  }

  /// Process-scoped, so host apps need no Info.plist entry. Returns the
  /// PostScript name, or nil if the file is missing or unreadable.
  private static func register(_ font: URL) -> String? {
    guard FileManager.default.fileExists(atPath: font.path),
      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(font as CFURL)
        as? [CTFontDescriptor],
      let name = descriptors.first.flatMap({
        CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
      })
    else { return nil }
    var error: Unmanaged<CFError>?
    if !CTFontManagerRegisterFontsForURL(font as CFURL, .process, &error),
      let error = error?.takeRetainedValue(),
      CFErrorGetCode(error) != CTFontManagerError.alreadyRegistered.rawValue
    {
      return nil
    }
    return name
  }

  /// Full file names and extensions → devicon names. Every name was checked
  /// against devicon v2.17.0; one a later release drops just falls back to `doc`.
  static let table: [String: String] = [
    // Full file names
    "dockerfile": "docker", "cmakelists.txt": "cmake", "package.json": "npm",
    "gemfile": "ruby", "cargo.toml": "rust", "go.mod": "go", "package.swift": "swift",
    "build.gradle": "gradle", ".gitignore": "git", ".gitattributes": "git",
    ".gitmodules": "git",
    // Extensions
    "swift": "swift", "m": "objectivec", "mm": "objectivec", "c": "c", "h": "c",
    "cpp": "cplusplus", "cc": "cplusplus", "cxx": "cplusplus", "hpp": "cplusplus",
    "cs": "csharp", "go": "go", "rs": "rust", "py": "python", "rb": "ruby", "java": "java",
    "kt": "kotlin", "kts": "kotlin", "scala": "scala", "js": "javascript", "mjs": "javascript",
    "cjs": "javascript", "jsx": "react", "ts": "typescript", "tsx": "react", "html": "html5",
    "htm": "html5", "css": "css3", "scss": "sass", "sass": "sass", "json": "json",
    "md": "markdown", "markdown": "markdown", "yml": "yaml", "yaml": "yaml", "xml": "xml",
    "sh": "bash", "bash": "bash", "zsh": "bash", "ps1": "powershell", "php": "php",
    "lua": "lua", "dart": "dart", "ex": "elixir", "exs": "elixir", "erl": "erlang",
    "hs": "haskell", "clj": "clojure", "r": "r", "jl": "julia", "pl": "perl", "vue": "vuejs",
    "svelte": "svelte", "graphql": "graphql", "gql": "graphql", "tf": "terraform",
    "nix": "nixos", "zig": "zig", "vim": "vim", "gradle": "gradle", "cmake": "cmake",
    "ipynb": "jupyter", "tex": "latex", "ml": "ocaml", "fs": "fsharp", "groovy": "groovy",
    "sol": "solidity", "cr": "crystal", "nim": "nim",
  ]
}
