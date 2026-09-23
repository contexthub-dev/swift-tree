# DevIcons

File-type icons come from [devicon](https://github.com/devicons/devicon) (MIT).
Run `make fonts` to download the latest release into this folder:

- `devicon.ttf`: the icon font
- `devicon-map.json`: icon name → glyph codepoint, generated from that release's CSS
- `LICENSE-devicon`: devicon's license, which must ship with the font
- `VERSION`: the devicon release tag

These files are gitignored on `main`. Release tags carry them (see
`.github/workflows/release.yml`), so SwiftPM consumers get the font without
running anything. Without them the tree still builds and file rows show the
generic `doc` icon.

Only this README is committed: SwiftPM fails the build if a declared resource
folder is missing.
