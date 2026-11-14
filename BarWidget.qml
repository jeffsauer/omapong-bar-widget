import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar entry point for the Omapong plugin.
//
// The two paddles and a ball make a readable Pong mark in the bar. A
// press toggles the game popout (Panel.qml). This widget owns the panel
// instance through a Loader that stays active between showings, so a
// round in progress survives being dismissed by an outside click.
//
// open/close/toggle/closeForPopoutSwitch and the `opened` /
// `popoutSwitchClosing` states are the shape the bar's popout
// coordinator talks to: it reads `opened` to light the button while a
// popout is up, hands the slot to this widget via requestPopout, and
// calls closeForPopoutSwitch when another popout takes it.
BarWidget {
  id: root

  moduleName: "io.github.jeffsauer.omapong"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false

  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // The panel needs the bar host to position and coordinate its popout,
  // the button to hang the card from, and itself as coordinator owner.
  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader

    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // The Pong mark: two paddles and a ball, composed as drawn shapes rather
  // than font glyphs. Block glyphs like "▮•▮" are not icon-font codepoints,
  // so WidgetButton would paint them as plain text at whatever height the
  // font dictates — this mark was a hair taller and heavier than every
  // neighbouring icon. BarIconButton hands the component to BarIconContent,
  // which normalises the drawing so a 12-tall artwork paints at exactly
  // Style.bar.iconSize, the same optical size the bar's own icons use,
  // centred in the same 27-wide icon slot. The mark is mid-rally, not a
  // still life: the machine's paddle stands at the top of its side, the
  // player's at the bottom of theirs, and the ball crosses between them a
  // third of the way down.
  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        width: 13
        height: 12

        // Machine paddle, riding high on the right.
        Rectangle {
          x: 10.5
          y: 0
          width: 2.5
          height: 7
          radius: width / 2
          color: button.foreground
        }

        // Player paddle, sunk low on the left.
        Rectangle {
          x: 0
          y: 5
          width: 2.5
          height: 7
          radius: width / 2
          color: button.foreground
        }

        // The ball, a third of the way down between the paddles.
        Rectangle {
          x: (parent.width - width) / 2
          y: Math.round(parent.height / 3 - height / 2)
          width: 3
          height: 3
          radius: width / 2
          color: button.foreground
        }
      }
    }
    tooltipText: "Omapong"

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
