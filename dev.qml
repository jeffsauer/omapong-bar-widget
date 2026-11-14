import QtQuick
import Quickshell

// Standalone development harness — not a plugin entry point.
//
// Runs the plugin's real Panel.qml (game window) and BarWidget-free, so the
// game can be developed without restarting the shell:
//
//   QML_IMPORT_PATH=/usr/share/omarchy/shell qs -c dev.qml
//
// qs.Commons and qs.Ui live under /usr/share/omarchy/shell, so they must be on
// the import path for the theme-aware pieces to resolve. The harness stays in
// this directory: the QML scanner blackholes Loader sources that point at a
// parent directory, which would silently leave no window at all.
//
// The original single-file standalone version is still here as omapong.qml
// and runs on its own with `qml omapong.qml`; the plugin copy above is the
// one installed in the bar.
ShellRoot {
  Loader {
    id: panelLoader

    source: "Panel.qml"
    onLoaded: if (item) item.open()
  }
}
