import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Panel entry point for the Omapong plugin: the game inside a popout
// anchored to the bar, built on the same parts Omarchy's own popups use.
//
// qs.Ui's KeyboardPanel is a full-screen overlay with the card hung from
// the bar strip, and it owns the dismissal model this game wants:
//
//   - Any real mouse click outside the card lands on the overlay and
//     closes the panel. Clicks on other bar icons are forwarded, so one
//     click swaps to another popout the way the built-ins do. And a
//     transparent twin overlay on every other monitor catches the click
//     there too, because the compositor hit-tests pointer input per
//     output.
//   - Window focus is separate. The keyboard primes onto the surface,
//     but when focus wanders off on its own, nothing here closes:
//     Game.qml's input layer just sees its active focus drop and holds
//     the round. Only clicking sends the game away.
//
// Away is always paused, never a forfeit: closing drops `opened`, the
// game's `active` flag follows, and that pauses the round. The bar
// widget's Loader keeps this instance alive between showings, so the
// next summon paints the round exactly where the click interrupted it,
// held behind the click-to-continue card. The one exception is Escape:
// mid-round it stops at an abandon prompt inside the game itself —
// answering yes there resets the round to a fresh game before this
// panel closes, so the next summon greets you with the wordmark and a
// 0-0 scoreboard instead of the round you abandoned.
Panel {
  id: root

  moduleName: "io.github.jeffsauer.omapong"

  // The bar widget's lifecycle is driven by the bar coordinator (widget
  // open/close/toggle), so the Panel base must not also register IPC for
  // it, same as the other game plugin on this machine does.
  manageIpc: false

  // Injected by BarWidget.qml: the bar host, the bar button this popout
  // hangs from, and the widget that acts as the popout's owner in the
  // bar's single-popout-per-bar coordinator.
  property var anchorItem: null
  property var hostWidget: null

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  KeyboardPanel {
    id: panel

    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened

    // Centred under the bar across the whole screen: the same top-centre
    // spot the game opened in before, with the popout's hang-from-the-
    // bar feel.
    centerOnBar: true

    // The playfield is designed for 900x600, and Game.fitToField rescales
    // to whatever the card hands it. Padding zero for the same reason the
    // card game next door sets it: the layout runs edge to edge, and the
    // default padding would shave the playfield.
    padding: 0
    contentWidth: 900
    contentHeight: 600

    // KeyboardPanel force-focuses this item the moment the surface owns
    // the keyboard. The target has to be the item that carries the Keys
    // handlers, not the Game root: forceActiveFocus lands on the target
    // itself, and a target with no handlers just holds the focus and
    // drops every key. Game.qml exposes its focusing input layer here.
    focusTarget: game.inputTarget

    Game {
      id: game

      anchors.fill: parent
      active: root.opened
      // Escape now asks before it destroys: Game.qml raises its
      // abandon prompt mid-round, and a "yes" has already reset the
      // round to a fresh game before the signal got here — so this
      // handler is just the close.
      onEscapeRequested: root.close()
    }
  }
}
