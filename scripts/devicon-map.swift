// Prints devicon's icon name → glyph codepoint map as JSON, read from the
// release's devicon.min.css. Exits 1 if it finds no glyphs, so a changed CSS
// format fails the fetch instead of shipping an empty map.
//
// Usage: swift scripts/devicon-map.swift devicon.min.css > devicon-map.json
import Foundation

guard CommandLine.arguments.count == 2,
  let css = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
else {
  FileHandle.standardError.write(Data("usage: devicon-map.swift <devicon.min.css>\n".utf8))
  exit(1)
}

// One rule can list several selectors: `.devicon-a:before,.devicon-b:before{content:"…"}`.
// The glyph is either the literal character or a `\e9a1`-style escape.
let rule = #/((?:\.devicon-[a-z0-9-]+:before,?)+)\{content:"(\\[0-9a-fA-F]+|[^"\\])"\}/#
let selector = #/\.devicon-([a-z0-9-]+):before/#

var map: [String: String] = [:]
for match in css.matches(of: rule) {
  let glyph = String(match.2)
  let code =
    glyph.hasPrefix("\\")
    ? glyph.dropFirst().lowercased()
    : String(glyph.unicodeScalars.first!.value, radix: 16)
  for name in match.1.matches(of: selector) { map[String(name.1)] = code }
}

guard !map.isEmpty else {
  FileHandle.standardError.write(Data("devicon-map.swift: no glyph rules found\n".utf8))
  exit(1)
}
let json = try JSONSerialization.data(withJSONObject: map, options: [.sortedKeys, .prettyPrinted])
print(String(decoding: json, as: UTF8.self))
