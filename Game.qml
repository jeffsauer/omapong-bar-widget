import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Balance.js" as Balance

// The Pong playfield, hosted by Panel.qml in its game window.
//
// A fresh summon greets the player with the OMAPONG wordmark, painted
// as a grid of square pixel cells — one line, cell size grown to the
// largest that fits the court's width, graded bright-to-dark top to
// bottom — the same blocky terminal look as the omarchy.org wordmark.
// It clears the moment the round begins: on the click that lifts the
// "click to begin" card, or on the first serve if that came first.
//
// Everything visual comes from qs.Commons.Color, so the game follows the live
// Omarchy theme the moment the theme changes — no palette to keep in sync.
//
// The round only runs while the player means it to: a click on the playfield
// toggles pause, and losing focus or hiding the window pauses it. A fresh
// window always opens paused, so a summoned game never starts moving under
// the player. And every rally ends only when the last ball in play crosses
// an end line: after that the game holds the score and goes to serve
// standby — both paddles free to reposition while the loser of the last
// rally readies its serve. A player server sets up with w/s and launches
// with space; the machine picks a mark, walks its paddle there, and fires
// on its own. On the opening screen the paddles wait at the court's
// thirds — player low, machine high — clear of the wordmark. Rallies get
// crowded — every so many strokes, a fresh ball joins play.
//
// Controls:
//   click           pause / resume (also releases the player's serve)
//   Space           serve during standby; pause / resume in a rally;
//                   restart once the round is over
//   W / S or Up / Down    move the left paddle (also while serving)
//   R / Enter       restart after game over
//   Escape          live round: ask "Abandon current game (Y/N)?";
//                   y restarts fresh and closes, n (or Esc again)
//                   keeps playing. Not started / already over: close
Item {
  id: game

  // Set by the host: the window is on screen, so the loop may run.
  property bool active: false

  signal escapeRequested()

  // The item KeyboardPanel should force active focus onto when the panel
  // opens. Must be the input layer itself: forceActiveFocus lands on the
  // target item, and only the layer carries the Keys handlers, so aiming
  // at the Game root would grab the focus and then drop every key.
  readonly property Item inputTarget: inputLayer

  function requestInputFocus() {
    inputLayer.forceActiveFocus()
  }

  property int playerScore: 0
  property int aiScore: 0
  property int totalScore: playerScore + aiScore
  property int rallyCount: 0
  property bool gameOver: false

  // Leaving mid-round is a deliberate act, so Escape asks first: while
  // the round is live, an Escape press raises the abandon prompt and
  // holds the game until it is answered — y or the Yes button hands the
  // round back fresh and closes, n or the No button (or a second
  // Escape) drops the prompt and picks the round back up. A round that
  // never started has nothing to abandon, and a finished one needs no
  // permission — Escape skips the question and closes those straight
  // to a fresh game, as it always has.
  property bool abandonPrompt: false

  // A round waits for the player. Opening the window, losing focus, or hiding
  // it all land here, so resuming is always a deliberate click.
  property bool paused: true

  // False until the ball has actually been in play this round, which is what
  // decides whether the paused card offers "begin" or "continue".
  property bool roundStarted: false

  // The wordmark is the round's opening impression, and it retires through
  // whichever door comes first: the first ball served, or the click that
  // lifts the "click to begin" card. introCleared marks the second door —
  // set every time the round is released from a hold, so the wordmark goes
  // away in the same breath as the card rather than lingering through the
  // opening standby. A restart re-arms it for the fresh round.
  property bool introCleared: false

  function togglePause() {
    if (game.gameOver)
      return

    game.paused = !game.paused

    if (!game.paused)
      beginPlay()
  }

  // Serve standby. waitingToServe marks the gap between rallies: no ball
  // is in play, both paddles are free to move, and the serve belongs to
  // the server — "player" launches it with space, the machine serves on
  // its own once its paddle reaches the mark aiServeTarget picked for it.
  // The machine holds at its mark briefly (aiServeCount frames) before
  // firing, so its serve is a deliberate beat rather than an instant snap.
  property bool waitingToServe: false
  property real aiServeTarget: 0
  property int aiServeDelay: 25

  // Where the paddles stand on the opening screen, before the round's
  // first serve: the player at the court's lower third, the machine
  // full-height near the top of the gap between the scoreboard shelf
  // and the wordmark's top edge — hugging the shelf, with most of the
  // pocket left below it, so the paddle reads as part of the head of
  // the court rather than crowding the logo. The wordmark spans nearly
  // the whole court width across the middle, so starting both paddles
  // outside its band keeps the logo clean until the first serve clears
  // it.
  function setOpeningPaddles() {
    playerCenterY = field.height * 5 / 6
    aiPaddle.y = clamp(plateBottom()
      + (logoTop() - plateBottom() - paddleHeight) / 4,
      0, field.height - paddleHeight)
  }

  // Put the game into standby: decide who serves the next rally. The
  // loser of the rally that just ended always serves, and at the start
  // of a match a random side opens. The player's serve waits on space;
  // the machine's waits on its own paddle.
  function enterServeWait() {
    waitingToServe = true
    if (!lastLoser)
      server = Math.random() < 0.5 ? "player" : "ai"
    else
      server = lastLoser
    if (!roundStarted) {
      // The opening serve: the machine marks out in the same pocket it
      // starts in — between the shelf and the wordmark — so the whole
      // standby stays clear of the logo.
      var openingMax = Math.max(paddleHeight / 2, aiPaddle.y + paddleHeight / 2)

      aiServeTarget = paddleHeight / 2
        + Math.random() * (openingMax - paddleHeight / 2)
    } else {
      aiServeTarget = paddleHeight / 2
        + Math.random() * (field.height - paddleHeight)
    }
    aiServeCount = aiServeDelay
  }

  // Launch the standby ball from wherever the server's paddle stands.
  function serveNow() {
    if (!waitingToServe)
      return

    waitingToServe = false
    serveBall()
  }

  function pauseGame() {
    game.paused = true
    game.clearHeldKeys()
  }

  // The rally has ended — its last ball just crossed an end line — and the
  // next one waits to be put in play. The game is not frozen: both paddles
  // can reposition, and then the serving side launches the ball. A player
  // who serves does it themselves — w/s to set up, space to put the ball
  // in play. The machine places its own paddle on a mark it picks and
  // fires once it is settled there. The score holds on the scoreboard
  // through all of it.
  function scorePause() {
    enterServeWait()
    clearHeldKeys()
  }

  // Leaving paused: focus the key catcher and drop any key that was somehow
  // held across the pause, so the paddle does not lurch on the first frame.
  // Leaving paused also retires the wordmark, so it and the card clear
  // together.
  function beginPlay() {
    game.clearHeldKeys()
    game.introCleared = true
    Qt.callLater(game.requestInputFocus)
  }

  property bool upPressed: false
  property bool downPressed: false

  // Sound. The game always opens muted — this window pops out of the bar
  // uninvited, and a pong that makes noise the moment it appears is not a
  // welcome guest — and "m" unmutes or mutes at any time, even mid-rally.
  property bool muted: true

  // Held keys are stale the moment the window goes away, and a window that is
  // gone is a round the player did not finish on purpose: pause it.
  onActiveChanged: if (!active) pauseGame()
  function clearHeldKeys() {
    game.upPressed = false
    game.downPressed = false
  }

  // Field and object sizes.
  property int margin: 30
  property int paddleWidth: 14
  property int paddleHeight: 100
  property int ballRadius: 10
  property int winScore: 11

  // The match names: the user on this machine plays the left paddle, and the
  // machine itself takes the right one. The username comes from the shell's
  // environment; the hostname is not reliably in that environment, so it is
  // read from /etc/hostname the way the agents plugin reads it. The generic
  // "you"/"ai" labels stay as fallbacks until a name is known.
  property string machineName: Quickshell.env("HOSTNAME")

  readonly property string playerName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || "you"
  readonly property string aiName: machineName || "ai"

  FileView {
    id: machineFile

    path: "/etc/hostname"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var name = String(text() || "").trim().split(".")[0]
      if (name && !game.machineName)
        game.machineName = name
    }
  }

  // Difficulty tuning constants. Raise for a harder game, lower for easier.
  property real baseBallSpeed: 6.0
  property real maxBallSpeed: 14.5
  property real basePlayerSpeed: 7.5
  property real baseAISpeed: 4.2

  // The machine's returns come off its paddle softer than the player's, by
  // this scale (the player's strokes and both sides' serves stay full
  // speed). This is the machine's scoring power turned down: balls reach
  // the player's paddle slower and less sharply angled, so covering two of
  // them at once stops being a coin flip — and the slower crossings stretch
  // rallies back out rather than shortening them.
  property real machineHitScale: 0.83

  // The balance line: the share of the points on offer that the game is
  // built to hand the player. Every catch-up term below reads the score
  // measured against this line rather than the raw score, so the player's
  // odds on any given point hold near six in ten whatever the scoreboard
  // says — short of the line the help leans the player's way and past it
  // the same terms turn on them.
  property real playerRallyTarget: 0.6

  // Rubber-band (catch-up) tuning: how hard play leans back toward
  // whichever side is furthest from the balance line. The machine tracks
  // the ball near exactly, and perfect tracking is unbeatable — every
  // straight ball comes back, and the only way to lose is to blink first.
  // So the lead is made to cost: the machine aims wider and moves slower
  // the further it trails the line, while the player's paddle gains reach
  // and speed the further behind the line it is — and past the line the
  // machine tightens and sharpens instead. Scale all of it by the distance
  // from the line, and neither side gets an unearned runaway.
  property real gapSpeedStep: 0.55  // paddle px/frame per point from the line
  property real baseAimWobble: 34   // px of machine aim error at the line, even rally
  property real gapAimStep: 14      // px of machine aim error per point from the line
  property real minAimWobble: 14    // the aim never tightens past this
  property real maxAimWobble: 90    // or wanders past this
  property real rallyAimStep: 0.75  // extra px of machine aim error per rally hit
  property real gapPaddleStep: 16   // px of player reach per point behind, past one
  property real maxGapPaddle: 80    // the reach never stretches further
  property int gapServeAt: 2        // distance from the line at which serves turn hot
  property real gapServeStep: 2     // extra serve px/frame per point behind

  // Who lost the rally that just ended: "player", "ai", or "" before the
  // first point of a match. The loser always serves next, and the serve
  // leaves their paddle — concede a point and the next one is yours to
  // open, from wherever you move your paddle to during the standby that
  // follows the rally.
  property string lastLoser: ""

  // Which side serves the standby ball ("player" or "ai"), chosen by
  // enterServeWait, and the machine's frames of settle before it fires.
  property string server: ""
  property int aiServeCount: 0

  // The distance from the balance line, in points: the raw score
  // difference read against the share of points playerRallyTarget gives
  // the player, so at the line — 60% of the points played on either
  // side's scoreboard — the gap reads zero and every catch-up term sits
  // neutral. A positive scoreGap means the player trails that line, which
  // is the direction all the catch-up terms lean in.
  readonly property real scoreGap: (aiScore - playerScore)
    + (2 * playerRallyTarget - 1) * totalScore

  // The player paddle's height: the base paddle, plus the stretch earned
  // while behind the line. The drawing and the collision read the same
  // property, so the help is never hidden from the player's own eyes.
  readonly property real playerReach: paddleHeight
    + Math.min(maxGapPaddle, Math.max(0, scoreGap - 1) * gapPaddleStep)

  // The two surfaces labels sit on: the court's field, and the more
  // deeply shaded scoreboard plate.
  readonly property color fieldSurface: Commons.Color.background.darker(1.18)
  readonly property color plateSurface: Commons.Color.background.darker(1.7)

  // Small label text — names, rally counter, status line, card lines —
  // takes the theme's muted tone, but never so dim against its surface
  // that it stops being readable: see Balance.js. The stricter floors
  // (5.5-6) are the 46px digits and 12px fine print; the ghost ball
  // carries a softer floor, as a decoration that should still
  // register on the dimmest themes.
  function labelColor(surface, want) {
    return Balance.labelColor(Commons.Color.muted, Commons.Color.foreground,
      surface, want)
  }

  readonly property color plateLabelColor: labelColor(plateSurface, 5.0)
  readonly property color fieldLabelColor: labelColor(fieldSurface, 5.0)

  // The player paddle is positioned by its centre, so the catch-up stretch
  // grows it evenly up and down instead of dragging it along by its top.
  property real playerCenterY: 300

  // How far off the machine's aim drifts, re-rolled at each serve.
  property real aiAimOffset: 0

  // Every ball in play, in field coordinates: live Rectangles from
  // ballComponent, each carrying its own position and velocity. A miss no
  // longer ends a rally on its own — it retires one ball and scores — the
  // rally ends only when this list runs empty. And the list grows on a
  // schedule: every ballSpawnHits strokes of the rally, a fresh ball joins
  // play from the centre line, off in a random direction.
  property var balls: []
  property int ballSpawnHits: 15  // rally strokes between new balls
  property int maxBalls: 6        // the chaos tops out here, well past any
                                  // rally a human actually plays to

  // Resizing the window changes the field, so keep the ball and both paddles
  // inside it rather than letting a drag push the round out of bounds.
  onWidthChanged: fitToField()
  onHeightChanged: fitToField()

  function fitToField() {
    for (var i = 0; i < game.balls.length; i += 1) {
      var b = game.balls[i]
      b.posX = clamp(b.posX, ballRadius, Math.max(ballRadius, field.width - ballRadius))
      b.posY = clamp(b.posY, ballRadius, Math.max(ballRadius, field.height - ballRadius))
    }

    playerCenterY = clamp(playerCenterY, playerReach / 2,
      Math.max(playerReach / 2, field.height - playerReach / 2))
    aiPaddle.y = clamp(aiPaddle.y, 0, Math.max(0, field.height - paddleHeight))
  }

  // ---------------------------------------------------------------------
  // Visual layout
  // ---------------------------------------------------------------------

  // Click anywhere to pause or resume. Declared first, so it sits under the
  // playfield: Rectangles take no mouse events, which lets the clicks fall
  // through to here, while the Restart button above keeps its own clicks.
  MouseArea {
    id: clickLayer

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: game.paused && !game.gameOver && !game.abandonPrompt
      ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: game.togglePause()
  }

  Rectangle {
    id: field

    x: game.margin
    y: game.margin
    width: game.width - 2 * game.margin
    height: game.height - 2 * game.margin
    color: Commons.Color.background.darker(1.18)
    border.color: Commons.Color.muted
    border.width: 2
    clip: true

    // The OMAPONG wordmark, shown until the round begins — the click
    // that lifts the card or the first serve, whichever comes first.
    // Painted as a grid of lit cells — exactly how the
    // omarchy.org wordmark is built (its logo file is a grid of square
    // cells), and free of any font's block-glyph metrics. It stands on
    // the centre line, with the pause card centered below it in the
    // court's lower half.
    Canvas {
      id: logoText

      // Its baseline — the bottom of the block's last letter row — sits
      // right on the court's centre line; the wordmark stands up from
      // the middle of the court. The cell size is the largest that
      // keeps the word on one line inside the court; at that size the
      // block's top stops just under the scoreboard plate's bottom
      // edge, and if the window ever shrinks enough for the top rows
      // to reach the plate, the logo is painted before the plate, so
      // the word reads as set behind the shelf.
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 0
      width: game.logoWidth() * game.logoPixel
      height: game.logoHeight() * game.logoPixel
      visible: !game.roundStarted && !game.introCleared && !game.gameOver
      antialiasing: false

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        // Gradient down the block: bright at the top row, dark at the
        // baseline. Built from the theme's foreground by pushing its
        // lightness up and down, so it follows the live theme.
        var c = Commons.Color.foreground
        var hi = Math.min(0.88, c.hslLightness + 0.20)
        var lo = Math.max(0.30, c.hslLightness - 0.34)
        var rows = game.logoHeight()

        var px = game.logoPixel
        var col = 0
        for (var i = 0; i < game.logoWord.length; i = i + 1) {
          if (game.logoWord[i] === " ") {
            col += 2
          } else {
            var glyph = game.logoPixelFonts[game.logoWord[i]]
            for (var r = 0; r < glyph.length; r = r + 1) {
              var t = r / (rows - 1)
              var light = hi + (lo - hi) * t
              ctx.fillStyle = Qt.hsla(c.hslHue, c.hslSaturation, light, 1.0)
              for (var g = 0; g < 5; g = g + 1) {
                if (glyph[r][g] === "1")
                  ctx.fillRect((col + g) * px, r * px, px, px)
              }
            }
            col += 5
          }
          if (i !== game.logoWord.length - 1)
            col += 1
        }
      }
    }

    // The head's three 46px bold numbers (player score, rally counter,
    // machine score) all take their top at this shared y, so with one
    // font their baselines coincide too — one invisible rule across the
    // scoreboard. 34 keeps them 20px below the scoreboard plate's top,
    // and the plate itself hangs 20px below the court's border line.
    // Declared up here, ahead of every number that uses it.
    readonly property real headTop: 34

    Rectangle {
      id: centerLine

      x: field.width / 2 - 1
      width: 2
      height: field.height
      color: Commons.Util.alpha(Commons.Color.muted, 0.55)
    }

    // The scoreboard plate. One opaque box hanging 20px below the court's
    // top border line, so the centre line disappears behind it instead of
    // crossing the rally counter. 340px wide, centred, rounded corners,
    // and outlined in the same grid-line style as the court's own border.
    Rectangle {
      id: scoreboard

      x: field.width / 2 - 170
      width: 340
      y: 20
      height: 92
      radius: 10
      color: Commons.Color.background.darker(1.7)
      border.color: Commons.Color.muted
      border.width: 2
    }

    // The match names, centred under their own score. The head also holds
    // the rally counter, in the middle between the digits, styled exactly
    // like them — same size, same weight — in the muted colour so it
    // reads as the middle voice of the scoreboard rather than a third
    // score, and it gets the same twin-blur flare on every stroke.
    Text {
      textFormat: Text.PlainText
      text: game.playerName
      color: game.plateLabelColor
      font.pixelSize: 14
      width: 130
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
      x: field.width / 2 - 120 - width / 2
      y: 90
    }

    Text {
      textFormat: Text.PlainText
      text: game.aiName
      color: game.plateLabelColor
      font.pixelSize: 14
      width: 130
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
      x: field.width / 2 + 120 - width / 2
      y: 90
    }

    // The rally counter, the middle voice of the scoreboard: same digits,
    // same twin-blur flare — fired whenever the stroke count ticks up,
    // which skips the reset between rallies — and a "rally" label under
    // the number that grows the live ball count once a second ball joins.
    Item {
      id: rallyScoreCell

      x: field.width / 2 - (rallyMainNumber.width + 48) / 2
      y: field.headTop - 24
      width: rallyMainNumber.width + 48
      height: rallyMainNumber.height + 48

      Text {
        id: rallyGlowNumber

        textFormat: Text.PlainText
        text: String(game.rallyCount)
        color: game.labelColor(game.plateSurface, 5.5)
        font.pixelSize: 46
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        anchors.fill: parent
        opacity: 0
        layer.enabled: true
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1.0
          blurMax: 31
        }

        SequentialAnimation {
          id: rallyFlare

          NumberAnimation {
            target: rallyGlowNumber
            property: "opacity"
            to: 1.0
            duration: 120
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: rallyGlowNumber
            property: "opacity"
            to: 0
            duration: 880
            easing.type: Easing.InOutQuad
          }
        }
      }

      Text {
        id: rallyMainNumber

        textFormat: Text.PlainText
        text: String(game.rallyCount)
        color: game.labelColor(game.plateSurface, 5.5)
        font.pixelSize: 46
        font.bold: true
        x: 24
        y: 24

        SequentialAnimation {
          id: rallyPop

          property real value: 1.0

          NumberAnimation {
            target: rallyPop
            property: "value"
            to: 1.15
            duration: 200
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: rallyPop
            property: "value"
            to: 1.0
            duration: 800
            easing.type: Easing.InOutQuad
          }
        }

        transform: Scale {
          xScale: rallyPop.value
          yScale: rallyPop.value
          origin.x: rallyMainNumber.width / 2
          origin.y: rallyMainNumber.height / 2
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      text: "rally"
        + (game.balls.length > 1 ? " · " + game.balls.length + " balls" : "")
      color: game.plateLabelColor
      font.pixelSize: 14
      horizontalAlignment: Text.AlignHCenter
      x: field.width / 2 - width / 2
      y: 90
    }

    // The two score cells, written out per side. Each stacks a blurred
    // twin of the digits under the digits themselves: the twin's opacity
    // is the flare, fired for a full second whenever that score changes,
    // while the digits pop a little in the same window. The twin is laid
    // out a third roomier than the digits, and blurred wide, so the halo
    // reads clearly before its layer's edge.

    // Player side, centred 120px left of the midline. Its number's top
    // sits at field.headTop (see the shared property above).
    Item {
      id: playerScoreCell

      x: field.width / 2 - 120 - (playerMainScore.width + 48) / 2
      y: field.headTop - 24
      width: playerMainScore.width + 48
      height: playerMainScore.height + 48

      Text {
        id: playerGlowScore

        textFormat: Text.PlainText
        text: String(game.playerScore)
        color: Commons.Color.accent
        font.pixelSize: 46
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        anchors.fill: parent
        opacity: 0
        layer.enabled: true
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1.0
          blurMax: 31
        }

        SequentialAnimation {
          id: playerFlare

          NumberAnimation {
            target: playerGlowScore
            property: "opacity"
            to: 1.0
            duration: 120
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: playerGlowScore
            property: "opacity"
            to: 0
            duration: 880
            easing.type: Easing.InOutQuad
          }
        }
      }

      Text {
        id: playerMainScore

        textFormat: Text.PlainText
        text: String(game.playerScore)
        color: Commons.Color.accent
        font.pixelSize: 46
        font.bold: true
        x: 24
        y: 24

        // The pop lives as data on the Text (transforms have no default
        // property to hold it) and drives the Scale below.
        SequentialAnimation {
          id: playerPop

          property real value: 1.0

          NumberAnimation {
            target: playerPop
            property: "value"
            to: 1.15
            duration: 200
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: playerPop
            property: "value"
            to: 1.0
            duration: 800
            easing.type: Easing.InOutQuad
          }
        }

        transform: Scale {
          xScale: playerPop.value
          yScale: playerPop.value
          origin.x: playerMainScore.width / 2
          origin.y: playerMainScore.height / 2
        }
      }
    }

    // Machine side, centred 120px right of the midline.
    Item {
      id: aiScoreCell

      x: field.width / 2 + 120 - (aiMainScore.width + 48) / 2
      y: field.headTop - 24
      width: aiMainScore.width + 48
      height: aiMainScore.height + 48

      Text {
        id: aiGlowScore

        textFormat: Text.PlainText
        text: String(game.aiScore)
        color: Commons.Color.urgent
        font.pixelSize: 46
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        anchors.fill: parent
        opacity: 0
        layer.enabled: true
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1.0
          blurMax: 31
        }

        SequentialAnimation {
          id: aiFlare

          NumberAnimation {
            target: aiGlowScore
            property: "opacity"
            to: 1.0
            duration: 120
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: aiGlowScore
            property: "opacity"
            to: 0
            duration: 880
            easing.type: Easing.InOutQuad
          }
        }
      }

      Text {
        id: aiMainScore

        textFormat: Text.PlainText
        text: String(game.aiScore)
        color: Commons.Color.urgent
        font.pixelSize: 46
        font.bold: true
        x: 24
        y: 24

        SequentialAnimation {
          id: aiPop

          property real value: 1.0

          NumberAnimation {
            target: aiPop
            property: "value"
            to: 1.15
            duration: 200
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: aiPop
            property: "value"
            to: 1.0
            duration: 800
            easing.type: Easing.InOutQuad
          }
        }

        transform: Scale {
          xScale: aiPop.value
          yScale: aiPop.value
          origin.x: aiMainScore.width / 2
          origin.y: aiMainScore.height / 2
        }
      }
    }

    // Status line, split across the bottom of the court: the round's
    // controls ride the left edge, the two always-live toggles — mute and
    // close — sit right-aligned on the right edge.
    Text {
      textFormat: Text.PlainText
      text: "spacebar - serve/pause, w/s - positions paddle"
      color: game.labelColor(game.fieldSurface, 6.0)
      font.pixelSize: 12
      x: 12
      y: field.height - 24
    }

    Text {
      textFormat: Text.PlainText
      text: "m - mute " + (game.muted ? "on" : "off") + ", esc - quit"
      color: game.labelColor(game.fieldSurface, 6.0)
      font.pixelSize: 12
      horizontalAlignment: Text.AlignRight
      x: field.width - width - 12
      y: field.height - 24
    }

    // One Rectangle per ball in play, made by addBall and retired by
    // removeBall. The motion lives in the plain posX/posY/velX/velY
    // properties — step() writes them every frame — and the x/y bindings
    // below are what actually move the pixels.
    Component {
      id: ballComponent

      Rectangle {
        property real posX: 0
        property real posY: 0
        property real velX: 0
        property real velY: 0

        width: game.ballRadius * 2
        height: game.ballRadius * 2
        radius: width / 2
        color: Commons.Color.foreground
        x: posX - game.ballRadius
        y: posY - game.ballRadius
      }
    }

    Rectangle {
      id: playerPaddle

      x: 28
      y: game.playerCenterY - game.playerReach / 2
      width: game.paddleWidth
      height: game.playerReach
      radius: 4
      color: Commons.Color.accent
    }

    Rectangle {
      id: aiPaddle

      x: field.width - game.paddleWidth - 28
      y: field.height / 2 - game.paddleHeight / 2
      width: game.paddleWidth
      height: game.paddleHeight
      radius: 4
      color: Commons.Color.urgent
    }

    // The standby ball, resting against the server's paddle while the
    // serve waits: a soft pulsing ghost for the player (their space key
    // launches it from here); invisible during the machine's own serve,
    // which needs no key and no hint.
    Rectangle {
      id: serveGhost

      width: game.ballRadius * 2
      height: game.ballRadius * 2
      radius: game.ballRadius
      color: Commons.Color.muted
      visible: game.waitingToServe && !game.gameOver && game.server === "player"
      opacity: serveGhostPulse.running ? serveGhostPulse.value : 0.7

      SequentialAnimation {
        id: serveGhostPulse

        property real value: 0.7
        running: game.waitingToServe && !game.gameOver && game.server === "player"

        NumberAnimation {
          target: serveGhostPulse
          property: "value"
          to: 0.25
          duration: 700
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          target: serveGhostPulse
          property: "value"
          to: 0.7
          duration: 700
          easing.type: Easing.InOutSine
        }
      }
    }

    // Paused card. Shown whenever the round is held: a click paused it, focus
    // went away, or the window was hidden and is coming back. The wording
    // tells the player whether this is a round about to start or one already
    // in progress, which is the difference between a fresh summon and a
    // resume.
    Rectangle {
      id: pauseOverlay

      anchors.fill: parent
      visible: pauseOverlay.opacity > 0
      // The abandon prompt replaces this card rather than stacking on
      // top of it: askAbandon holds the round, and the question owns
      // the screen while it is up.
      opacity: game.paused && !game.gameOver && !game.abandonPrompt ? 1 : 0
      color: Commons.Util.alpha(Commons.Color.background, 0.62)

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
      }

      Column {
        id: pauseColumn

        // Centered in the court's lower half — the span between the
        // centre line (where the wordmark's baseline stands) and the
        // bottom line — so the card owns everything under the logo.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: parent.height / 4
        spacing: 12
        opacity: game.paused && !game.gameOver && !game.abandonPrompt ? 1 : 0
        scale: game.paused && !game.gameOver && !game.abandonPrompt ? 1 : 0.97

        Behavior on opacity {
          NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
          NumberAnimation {
            duration: Style.duration(180)
            easing.type: Easing.Bezier
            easing.bezierCurve: Style.easeOut
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: game.roundStarted ? "click to continue" : "click to begin"
          color: Commons.Color.foreground
          font.pixelSize: 26
          font.bold: true
        }

        // During serve standby the card's subtitle keeps the score, and a
        // third line teaches the serve: space launches it for a player
        // server; the machine's serve takes its own sweet time.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          visible: !game.waitingToServe
          text: game.roundStarted
            ? game.playerName + " " + game.playerScore + "  -  " + game.aiScore + " " + game.aiName
            : "first to " + game.winScore + " points wins the round"
          color: game.labelColor(game.fieldSurface, 5.5)
          font.pixelSize: 13
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          visible: game.waitingToServe
          text: game.server === "player" ? game.playerName + " to serve" : game.aiName + " to serve"
          color: game.fieldLabelColor
          font.pixelSize: 13
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: game.waitingToServe
            ? (game.server === "player"
              ? "w/s positions paddle, spacebar to serve"
              : "the machine lines up and serves on its own")
            : "space or click resumes   w/s positions the paddle"
          color: game.labelColor(game.fieldSurface, 5.5)
          font.pixelSize: 12
        }
      }
    }

    // Game over card. Grows in rather than appearing, which is the shell's
    // way of confirming the round ended.
    Rectangle {
      id: overlay

      anchors.fill: parent
      visible: overlay.opacity > 0
      opacity: game.gameOver ? 1 : 0
      color: Commons.Util.alpha(Commons.Color.background, 0.84)

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
      }

      Column {
        id: resultColumn

        anchors.centerIn: parent
        spacing: 18
        opacity: game.gameOver ? 1 : 0
        scale: game.gameOver ? 1 : 0.96

        Behavior on opacity {
          NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
          NumberAnimation {
            duration: Style.duration(180)
            easing.type: Easing.Bezier
            easing.bezierCurve: Style.easeOut
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: (game.playerScore > game.aiScore ? game.playerName : game.aiName) + " wins"
          color: Commons.Color.foreground
          font.pixelSize: 48
          font.bold: true
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "press r/space/enter or click restart"
          color: game.labelColor(game.fieldSurface, 5.5)
          font.pixelSize: 14
        }

        Button {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Restart"
          bordered: true
          onClicked: game.restartGame()
        }
      }
    }

    // Abandon prompt. Escape mid-round asks before it destroys: the
    // question holds the round under a dimmed field until it is
    // answered, by keyboard (y/n) or by the buttons. It owns the
    // mouse too — its own click layer swallows every click that is
    // not a button, so a stray click can neither resume the round
    // nor land on the field's click-to-resume layer.
    Rectangle {
      id: abandonOverlay

      anchors.fill: parent
      visible: abandonOverlay.opacity > 0
      opacity: game.abandonPrompt ? 1 : 0
      color: Commons.Util.alpha(Commons.Color.background, 0.84)

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
      }

      // Declared before the Column: later siblings stack above it,
      // which is how the Yes/No buttons keep their own clicks while
      // everything else dies here.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
      }

      Column {
        id: abandonColumn

        anchors.centerIn: parent
        spacing: 18
        opacity: game.abandonPrompt ? 1 : 0
        scale: game.abandonPrompt ? 1 : 0.96

        Behavior on opacity {
          NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
          NumberAnimation {
            duration: Style.duration(180)
            easing.type: Easing.Bezier
            easing.bezierCurve: Style.easeOut
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "Abandon current game (Y/N)?"
          color: Commons.Color.foreground
          font.pixelSize: 34
          font.bold: true
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "yes exits game, no continues this one"
          color: game.labelColor(game.fieldSurface, 5.5)
          font.pixelSize: 13
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 14

          Button {
            text: "Yes"
            bordered: true
            onClicked: game.answerAbandon(true)
          }

          Button {
            text: "No"
            bordered: true
            onClicked: game.answerAbandon(false)
          }
        }
      }
    }
  }

  // A score change fires that side's glow flare: a full second of blurred
  // halo behind the digits plus a small scale pop. A reset to 0 stays
  // quiet. The handlers sit on the root, beside the properties whose
  // change signals they catch.
  onPlayerScoreChanged: {
    if (playerScore !== 0)
      pulsePlayerScore()
  }
  onAiScoreChanged: {
    if (aiScore !== 0)
      pulseAiScore()
  }
  onRallyCountChanged: {
    if (rallyCount !== 0)
      pulseRallyCounter()
  }

  function pulsePlayerScore() {
    playerFlare.restart()
    playerPop.restart()
  }

  function pulseAiScore() {
    aiFlare.restart()
    aiPop.restart()
  }

  function pulseRallyCounter() {
    rallyFlare.restart()
    rallyPop.restart()
  }

  // ---------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------

  Item {
    id: inputLayer

    anchors.fill: parent
    focus: true

    // A round is held the moment the window stops being the focused one: the
    // player has gone somewhere else, so coming back should be a choice
    // rather than a ball already in motion. Clicking the Restart button takes
    // focus too, and restartGame picks the round straight back up.
    onActiveFocusChanged: {
      if (activeFocus)
        return

      if (game.gameOver)
        game.clearHeldKeys()
      else
        game.pauseGame()
    }

    Keys.onPressed: function (event) {
      // Mute toggle, valid in any state: the round does not care, and
      // neither should the volume knob.
      if (event.key === Qt.Key_M) {
        game.muted = !game.muted
        event.accepted = true
        return
      }

      // The abandon prompt owns the keyboard while it is up: y and n
      // answer it, and every other key is swallowed so nothing leaks
      // into the held round behind it.
      if (game.abandonPrompt) {
        if (event.key === Qt.Key_Y)
          game.answerAbandon(true)
        else if (event.key === Qt.Key_N)
          game.answerAbandon(false)
        event.accepted = true
        return
      }

      // Round over: these keys start a new one.
      if (game.gameOver
          && (event.key === Qt.Key_Space
              || event.key === Qt.Key_R
              || event.key === Qt.Key_Return
              || event.key === Qt.Key_Enter)) {
        game.restartGame()
        event.accepted = true
        return
      }

      // In play, Space is the pause toggle, in either direction, so
      // pausing never needs the mouse. During serve standby, Space serves:
      // if the player holds the serve, it puts the ball in play from the
      // paddle's mark; if the machine holds it, space does nothing — the
      // machine fires on its own. Standby is not a pause: click the
      // playfield to freeze one.
      if (game.waitingToServe && event.key === Qt.Key_Space) {
        if (game.server === "player")
          serveNow()
        event.accepted = true
        return
      }

      if (event.key === Qt.Key_Space) {
        game.togglePause()
        event.accepted = true
        return
      }

      // Enter also releases a held round, for the player who never left the
      // keyboard.
      if (game.paused
          && (event.key === Qt.Key_Return
              || event.key === Qt.Key_Enter)) {
        game.togglePause()
        event.accepted = true
        return
      }

      if (event.key === Qt.Key_Up || event.key === Qt.Key_W) {
        game.upPressed = true
        event.accepted = true
      } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
        game.downPressed = true
        event.accepted = true
      }
    }

    Keys.onReleased: function (event) {
      if (event.key === Qt.Key_Up || event.key === Qt.Key_W)
        game.upPressed = false
      else if (event.key === Qt.Key_Down || event.key === Qt.Key_S)
        game.downPressed = false
      else if (event.key === Qt.Key_Escape) {
        // Escape while the question is up means never mind: back out,
        // round exactly as it was. A live round asks first; a finished
        // one has nothing left to abandon and resets on the way out;
        // one that never started just goes.
        if (game.abandonPrompt)
          game.answerAbandon(false)
        else if (game.roundStarted && !game.gameOver)
          game.askAbandon()
        else if (game.gameOver) {
          game.restartGame()
          game.escapeRequested()
        } else
          game.escapeRequested()
        event.accepted = true
      }
    }
  }

  // The loop runs only while the window is on screen and the player has
  // released the round: a hidden or paused game costs the shell nothing and
  // picks up exactly where it left off. Serve standby is the one exception
  // to the pause freeze — a paused game still runs its frames while
  // waitingToServe holds, because positioning the paddles is not something
  // to wait on.
  Timer {
    id: gameTimer

    interval: 16
    running: game.active && !game.gameOver && (!game.paused || game.waitingToServe)
    repeat: true
    onTriggered: game.step()
  }

  Component.onCompleted: {
    setOpeningPaddles()
    enterServeWait()
  }

  // ---------------------------------------------------------------------
  // Game logic
  // ---------------------------------------------------------------------

  // The wordmark's pixel font, all caps, one line: five cells wide,
  // five rows tall for every letter, so the word sits on one clean
  // baseline. The blocky grid look of the omarchy.org wordmark, which
  // is built from the same kind of square cells.
  property string logoWord: "OMAPONG"

  property var logoPixelFonts: ({
    O: ["01110", "10001", "10001", "10001", "01110"],
    M: ["10001", "11011", "10101", "10101", "10001"],
    A: ["01110", "10001", "11111", "10001", "10001"],
    P: ["11110", "10001", "11110", "10000", "10000"],
    N: ["10001", "11001", "10101", "10011", "10001"],
    G: ["01110", "10000", "10011", "10001", "01110"]
  })

  // Cell size in px: the largest that fits the word on one line across
  // the court — word cells plus one cell of breathing room on each
  // side — so the wordmark grows with the window instead of wrapping.
  readonly property int logoPixel: Math.max(4, Math.floor(field.width / (logoWidth() + 2)))

  // Cell rows the block occupies, and the word's cell count.
  function logoHeight() {
    return 5
  }

  function logoWidth() {
    var w = 0
    for (var i = 0; i < logoWord.length; i = i + 1)
      w += logoWord[i] === " " ? 2 : 5
    return w + (logoWord.length - 1)
  }

  // Where the wordmark's block begins inside the court — the canvas is
  // centred with its baseline on the centre line, so its top sits a
  // half-block above the middle. The paddles take their opening marks
  // with this edge in mind.
  function logoTop() {
    return field.height / 2 - logoHeight() * logoPixel / 2
  }

  // The scoreboard plate's bottom edge inside the court.
  function plateBottom() {
    return scoreboard.y + scoreboard.height
  }

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
  }

  // The game's three voices: ping for either paddle, thud for either wall,
  // and the whoosh of a ball getting past either paddle — both sides'
  // misses sound alike. QSoundEffect decodes once at load and plays from
  // memory after, so repeated hits never lag or stutter the way an
  // external player per hit would.
  SoundEffect {
    id: pingSound

    source: "sounds/ping.wav"
  }

  SoundEffect {
    id: thudSound

    source: "sounds/thud.wav"
  }

  SoundEffect {
    id: whooshSound

    source: "sounds/whoosh.wav"
  }

  function playEffect(effect) {
    if (!game.muted)
      effect.play()
  }

  function serveSpeed() {
    return Math.min(maxBallSpeed, baseBallSpeed + totalScore * 0.45)
  }

  function hitSpeed() {
    return Math.min(maxBallSpeed, baseBallSpeed + totalScore * 0.45 + rallyCount * 0.22)
  }

  function playerSpeed() {
    return Math.min(14,
      basePlayerSpeed + totalScore * 0.22 + Math.max(0, scoreGap) * gapSpeedStep)
  }

  function aiSpeed() {
    // The same distance from the line that stretches the player's paddle
    // costs the machine speed: trailing its share of the points, it simply
    // cannot cover the field the way it could at the line. Ahead of its
    // share, it sharpens — a player who runs up more than their 60% finds
    // a quicker opponent, not a free cruise to seven.
    var speed = baseAISpeed + totalScore * 0.35 + rallyCount * 0.09 - scoreGap * gapSpeedStep
    return clamp(speed, 3.5, 13)
  }

  // The machine never tracks the ball exactly: this offset is where that
  // error lives — it chases the tracked ball's Y plus this number. Rolled
  // at every serve and re-rolled at every stroke the player makes, so its
  // target keeps jumping mid-rally. Perfect tracking is unbeatable — a
  // steady exchange between two flawless players runs forever — so this
  // wobble is what ends rallies, and it rides the distance from the
  // balance line in both directions: a machine trailing its share of the
  // points plays sloppy, giving the player a way back to the line, and a
  // player past the line meets a machine that plays near its best. It also
  // grows with the rally itself, so a duel builds to a crescendo instead
  // of grinding on. Floored and capped, so even at hit one hundred the
  // machine is still playing pong — never perfect, never lost.
  function rollAim() {
    var sloppiness = clamp(baseAimWobble + scoreGap * gapAimStep
      + rallyCount * rallyAimStep, minAimWobble, maxAimWobble)
    aiAimOffset = (Math.random() * 2 - 1) * sloppiness
  }

  // The life cycle of a ball: created onto the field with its motion set,
  // retired when it crosses an end line. game.balls is reassigned rather
  // than pushed to, so bindings on the list see every change.
  function addBall(x, y, velX, velY) {
    var b = ballComponent.createObject(field)
    b.posX = x
    b.posY = y
    b.velX = velX
    b.velY = velY
    game.balls = game.balls.concat([b])
    return b
  }

  function removeBall(b) {
    b.destroy()
    game.balls = game.balls.filter(function (other) { return other !== b })
  }

  function clearBalls() {
    for (var i = 0; i < game.balls.length; i += 1)
      game.balls[i].destroy()
    game.balls = []
  }

  // A rally stroke by either paddle. The stroke count is what chaos keys
  // off: every ballSpawnHits strokes, another ball appears mid-court. As
  // long as the rally is competitive, the table keeps crowding, and every
  // extra ball in the air is another way for either side to finally blink.
  function registerHit() {
    rallyCount += 1
    game.playEffect(pingSound)

    if (rallyCount % ballSpawnHits === 0 && game.balls.length < maxBalls)
      spawnChaosBall()
  }

  function spawnChaosBall() {
    // Chaos enters at a random height on the centre line and leaves in a
    // random direction — the one concession is a real horizontal component,
    // so the new ball always travels toward one paddle or the other. A
    // ball launched straight up and down would only trade wall bounces
    // with itself, and a rally has to be able to end.
    var speed = serveSpeed()
    var dir = Math.random() < 0.5 ? 1 : -1
    var angle = (Math.random() * 2 - 1) * (Math.PI / 3)
    var y = ballRadius + Math.random() * (field.height - 2 * ballRadius)

    addBall(field.width / 2, y, dir * speed * Math.cos(angle), speed * Math.sin(angle))
  }

  // Launch the standby ball. A serve always means a fresh rally: whatever
  // balls survived the last one are swept away and a single ball is put
  // in play, from where the server's paddle currently stands, traveling
  // to the other end.
  function serveBall() {
    if (gameOver)
      return

    clearBalls()
    rallyCount = 0

    var speed = serveSpeed()

    var dir
    var serveX
    var serveY
    if (server === "player") {
      serveX = playerPaddle.x + paddleWidth + ballRadius
      serveY = playerCenterY
      dir = 1
    } else {
      serveX = aiPaddle.x - ballRadius
      serveY = aiPaddle.y + paddleHeight / 2
      dir = -1
    }

    // The serve rule hands the side that just scored the first attack of
    // the next rally — they receive the soft serve and set the terms — so
    // a lead feeds itself: score, receive, attack, score again. To break
    // that chain, the catch-up shows up in the serve itself: a side two
    // or more points short of the balance line fires the ball off its
    // paddle hot, and the other side gets far less time to set up the
    // return stroke. The bigger the shortfall, the hotter the serve, up
    // to the ball's normal cap.
    var behind = (server === "player") ? scoreGap : -scoreGap
    if (behind >= gapServeAt)
      speed = Math.min(maxBallSpeed, speed + (behind - 1) * gapServeStep)

    rollAim()

    // Random serve angle, limited to about +/- 36 degrees. The height is
    // no longer random: it is wherever the server chose to stand.
    var angle = (Math.random() * 2 - 1) * (Math.PI / 5)

    addBall(serveX, serveY, dir * speed * Math.cos(angle), speed * Math.sin(angle))
  }

  function step() {
    if (gameOver)
      return

    // The first serve frame is the round beginning, which is what makes
    // the paused card offer "continue" instead of "begin" for the rest
    // of it. The positioning frames before a serve do not count.
    if (!waitingToServe)
      roundStarted = true

    // Player paddle movement — live even in serve standby, so the
    // serving player can set up wherever they like before launching.
    var pSpeed = playerSpeed()

    if (upPressed)
      playerCenterY = clamp(playerCenterY - pSpeed, playerReach / 2, field.height - playerReach / 2)

    if (downPressed)
      playerCenterY = clamp(playerCenterY + pSpeed, playerReach / 2, field.height - playerReach / 2)

    // The standby ball rides against the player's paddle while they set
    // up, so the serve's launch point is plain to see.
    if (waitingToServe && server === "player") {
      serveGhost.x = playerPaddle.x + paddleWidth
      serveGhost.y = playerCenterY - game.ballRadius
    }

    // AI paddle movement. During serve standby it walks to the mark it
    // picked for the serve, counts a beat settled there, then fires; the
    // serve is its own, so no key ever acts for it. In play it chases
    // the ball that reaches it first — the incoming one nearest its own
    // edge — and re-centres when nothing is coming. The aim offset
    // shifts where "track" means, so the machine plays the ball where it
    // aims, not where it is — see serveBall's re-roll.
    if (waitingToServe) {
      if (server === "ai") {
        var markDelta = clamp(aiServeTarget - (aiPaddle.y + paddleHeight / 2),
          -aiSpeed(), aiSpeed())
        aiPaddle.y = clamp(aiPaddle.y + markDelta, 0, field.height - paddleHeight)

        // The countdown only runs while the question is not up: the
        // machine may finish gliding to its mark, but no ball goes in
        // play behind the abandon prompt.
        if (!game.abandonPrompt
            && Math.abs(aiServeTarget - (aiPaddle.y + paddleHeight / 2)) <= Math.max(2, aiSpeed())) {
          aiServeCount -= 1
          if (aiServeCount <= 0)
            serveNow()
        }
      }

      // In standby there is no ball to move yet; this frame belongs to
      // the paddles.
      return
    }

    var chase = null
    for (var i = 0; i < game.balls.length; i += 1) {
      var incoming = game.balls[i]
      if (incoming.velX > 0 && (chase === null || incoming.posX > chase.posX))
        chase = incoming
    }

    var target = chase !== null ? chase.posY + aiAimOffset : (field.height / 2)
    var aiCenter = aiPaddle.y + paddleHeight / 2
    var aiDelta = clamp(target - aiCenter, -aiSpeed(), aiSpeed())

    aiPaddle.y = clamp(aiPaddle.y + aiDelta, 0, field.height - paddleHeight)

    // Every ball in play moves and collides on the same frame. The loop
    // walks a snapshot: a ball retired by a miss mid-frame, or a chaos
    // ball born from a hit this same frame, changes the live list, but
    // this frame belongs to the balls that were in play when it began.
    var live = game.balls.slice()
    for (var j = 0; j < live.length && !gameOver; j += 1) {
      var ball = live[j]

      ball.posX += ball.velX
      ball.posY += ball.velY

      // Top/bottom wall bounce.
      if (ball.posY < ballRadius) {
        ball.posY = ballRadius
        if (ball.velY < 0) {
          ball.velY = -ball.velY
          game.playEffect(thudSound)
        }
      } else if (ball.posY > field.height - ballRadius) {
        ball.posY = field.height - ballRadius
        if (ball.velY > 0) {
          ball.velY = -ball.velY
          game.playEffect(thudSound)
        }
      }

      // Player paddle collision.
      if (ball.velX < 0
          && ball.posX <= playerPaddle.x + paddleWidth + ballRadius
          && ball.posX >= playerPaddle.x - ballRadius
          && ball.posY + ballRadius >= playerPaddle.y
          && ball.posY - ballRadius <= playerPaddle.y + playerReach) {

        ball.posX = playerPaddle.x + paddleWidth + ballRadius

        var playerOffset = (ball.posY - playerCenterY) / (playerReach / 2)
        playerOffset = clamp(playerOffset, -1, 1)

        // Avoid perfectly horizontal returns.
        if (Math.abs(playerOffset) < 0.05)
          playerOffset = (Math.random() < 0.5 ? -1 : 1) * 0.05

        var playerHitSpeed = hitSpeed()
        var playerAngle = playerOffset * (Math.PI / 4)

        ball.velX = playerHitSpeed * Math.cos(playerAngle)
        ball.velY = playerHitSpeed * Math.sin(playerAngle)

        registerHit()
        // Every stroke you take makes the machine re-guess where the ball
        // will be: its chase target jumps, and a rally that runs long enough
        // always forces the miss that ends it.
        rollAim()
      }

      // AI paddle collision.
      if (ball.velX > 0
          && ball.posX + ballRadius >= aiPaddle.x
          && ball.posX <= aiPaddle.x + paddleWidth + ballRadius
          && ball.posY + ballRadius >= aiPaddle.y
          && ball.posY - ballRadius <= aiPaddle.y + paddleHeight) {

        ball.posX = aiPaddle.x - ballRadius

        var aiOffset = (ball.posY - (aiPaddle.y + paddleHeight / 2)) / (paddleHeight / 2)
        aiOffset = clamp(aiOffset, -1, 1)

        // Avoid perfectly horizontal returns.
        if (Math.abs(aiOffset) < 0.05)
          aiOffset = (Math.random() < 0.5 ? -1 : 1) * 0.05

        var aiHitSpeed = hitSpeed() * machineHitScale
        var aiAngle = aiOffset * (Math.PI / 4)

        ball.velX = -aiHitSpeed * Math.cos(aiAngle)
        ball.velY = aiHitSpeed * Math.sin(aiAngle)

        registerHit()
      }

      // A miss retires its ball and scores, but the rally itself carries
      // on as long as any ball is still alive somewhere on the field.
      // Either side's miss gets the same whoosh — a ball leaving play
      // should sound like one no matter whose paddle it just got past.
      if (ball.posX <= 0) {
        aiScore += 1
        lastLoser = "player"
        game.playEffect(whooshSound)
        removeBall(ball)

        if (aiScore >= winScore)
          gameOver = true
      } else if (ball.posX >= field.width) {
        playerScore += 1
        lastLoser = "ai"
        game.playEffect(whooshSound)
        removeBall(ball)

        if (playerScore >= winScore)
          gameOver = true
      }
    }

    // The rally ends as it always did — on a ball crossing an end line —
    // but now it is the last ball crossing an end line that ends it. The
    // side that conceded that final ball is the rally's loser, so it is
    // the side the next serve leaves from.
    if (!gameOver && game.balls.length === 0)
      scorePause()
  }

  // Escape during a live round: hold the round (remembering whether it
  // was already held, so backing out restores exactly that) and raise
  // the prompt.
  property bool abandonWasPaused: false

  function askAbandon() {
    abandonWasPaused = paused
    pauseGame()
    abandonPrompt = true
  }

  function answerAbandon(leave) {
    abandonPrompt = false
    if (leave) {
      // Yes: the round is over as far as the player is concerned —
      // reset to a fresh game, then let the panel close. The close
      // lands in the same synchronous block, before the game timer
      // can fire, so the fresh state waits frozen behind the card
      // until the next summon.
      restartGame()
      escapeRequested()
    } else {
      // No: back to exactly the state Escape found — held or playing.
      paused = abandonWasPaused
      Qt.callLater(game.requestInputFocus)
    }
  }

  function restartGame() {
    playerScore = 0
    aiScore = 0
    rallyCount = 0
    gameOver = false
    lastLoser = ""
    clearHeldKeys()

    // Restarting is a deliberate act, so the new round goes straight to
    // serve standby and the paddles start positioning right away. It
    // still counts as not-yet-begun for the paused card's wording until
    // the first serve launches, and the wordmark is re-armed to greet
    // the fresh round.
    paused = false
    roundStarted = false
    introCleared = false

    setOpeningPaddles()

    enterServeWait()
    gameTimer.restart()

    Qt.callLater(game.requestInputFocus)
  }

  function resetGame() {
    gameOver = false
    restartGame()
  }
}
