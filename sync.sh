#!/usr/bin/env bash
# Install the development copy into the shell's plugin directory and reload it.
#
# A symlink is deliberately not used: `omarchy plugin validate` rejects a
# symlinked plugin folder, and a plain copy is what a published third-party
# plugin ships as anyway. Only the plugin's own files are installed — the
# development harness and the original standalone game stay here.

set -euo pipefail

ID="io.github.jeffsauer.omapong"
SRC="$(cd "$(dirname "$0")" && pwd)/"
DEST="${HOME}/.config/omarchy/plugins/${ID}"

mkdir -p "$DEST"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'dev.qml' \
  --exclude 'test.qml' \
  --exclude 'omapong.qml' \
  --exclude 'README.md' \
  --exclude 'sync.sh' \
  "$SRC" "$DEST/"

omarchy plugin validate "$DEST"
omarchy-shell shell reloadPlugins
echo "installed ${ID} -> ${DEST}"
