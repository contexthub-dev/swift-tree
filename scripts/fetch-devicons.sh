#!/usr/bin/env bash
# Downloads the latest devicon release (font, license, glyph map) into
# Sources/SwiftTree/Resources/DevIcons. Run through `make fonts`.
# Set GITHUB_TOKEN to avoid the anonymous GitHub API rate limit (CI does).
set -euo pipefail
cd "$(dirname "$0")/.."

dest=Sources/SwiftTree/Resources/DevIcons
fail() {
  echo "fetch-devicons: failed $1" >&2
  exit 1
}

# `${auth[@]+…}`: macOS bash 3.2 treats an empty array as unbound under `set -u`.
auth=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then auth=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi

tag=$(curl -fsSL ${auth[@]+"${auth[@]}"} https://api.github.com/repos/devicons/devicon/releases/latest |
  sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1) || fail "resolving the latest release"
[[ -n "$tag" ]] || fail "resolving the latest release (no tag_name in the response)"
# The tag goes into a URL and a committed file: accept only a plain version tag.
[[ "$tag" =~ ^v?[0-9]+(\.[0-9]+)*$ ]] || fail "resolving the latest release (unexpected tag '$tag')"

raw="https://raw.githubusercontent.com/devicons/devicon/$tag"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$raw/fonts/devicon.ttf" -o "$tmp/devicon.ttf" || fail "downloading devicon.ttf ($tag)"
curl -fsSL "$raw/devicon.min.css" -o "$tmp/devicon.min.css" || fail "downloading devicon.min.css ($tag)"
curl -fsSL "$raw/LICENSE" -o "$tmp/LICENSE-devicon" || fail "downloading LICENSE ($tag)"
swift scripts/devicon-map.swift "$tmp/devicon.min.css" >"$tmp/devicon-map.json" ||
  fail "generating the glyph map ($tag)"
echo "$tag" >"$tmp/VERSION"

cp "$tmp/devicon.ttf" "$tmp/devicon-map.json" "$tmp/LICENSE-devicon" "$tmp/VERSION" "$dest/"
echo "fetch-devicons: devicon $tag -> $dest"
