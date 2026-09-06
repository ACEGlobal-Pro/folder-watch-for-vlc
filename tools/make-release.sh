#!/bin/bash
# Builds dist/folder-watch-for-vlc-<version>.zip: the three scripts, installer, README, LICENSE, CHANGELOG, docs/LICENSING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -o 'local VERSION = "[^"]*"' lua/extensions/folderwatch.lua | cut -d'"' -f2)
OUT="dist/folder-watch-for-vlc-$VERSION"
rm -rf "$OUT" "$OUT.zip"; mkdir -p "$OUT"
cp -R lua install.sh README.md LICENSE CHANGELOG.md "$OUT/" && mkdir -p "$OUT/docs" && cp docs/LICENSING.md "$OUT/docs/"
(cd dist && zip -qr "folder-watch-for-vlc-$VERSION.zip" "folder-watch-for-vlc-$VERSION")
rm -rf "$OUT"
shasum -a 256 "$OUT.zip"
