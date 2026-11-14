import QtQuick
import Quickshell

// Balance harness — windowless Game instance with an embedded perfect-play
// bot, so match balance can be measured without keyboard focus, screenshots,
// or touching the running shell. Deliberately not installed by sync.sh.
//
// Setup (Quickshell adds the config's own directory to the import path, so
// symlinked Commons/Ui directories make the qs.Commons and qs.Ui modules
// resolve):
//
//   mkdir -p /tmp/pongrun && cd /tmp/pongrun
//   ln -sf /usr/share/omarchy/shell/Commons Commons
//   ln -sf /usr/share/omarchy/shell/Ui Ui
//   ln -sf ~/Data/Development/omapong/Game.qml Game.qml
//   cp ~/Data/Development/omapong/test.qml .
//   quickshell -p test.qml            # bot runs on its own, logging as it goes
//
// Logs: BALLOUT (each ball that leaves play mid-rally, with the running
// score), RALLY (per completed rally: total strokes, balls retired, and
// game-seconds from serve to the last ball gone), RESULT (per match),
// BALANCE (the whole run: the player's share of every point contested —
// that share is what the Game.qml balance line aims at 0.60), ALLDONE.
//
// The whole harness runs 8x fast: fastForward() finds the game's own 16ms
// Timer through the item's data list and retunes it to 2ms, so ten matches
// take a few real minutes instead of an hour and a half. Measurement is
// still in game time: every game frame moves every ball, so the sum of all
// balls' positions advances exactly once per frame; frames counted that way
// times 16ms is true rally time — unaffected by the tick scale.
//
// The bot plays one of two ways. Flawless (the default) is the ceiling:
// full chase, edge hits for steep angles — but with several balls in play
// one paddle cannot cover every one, and even a flawless player starts
// conceding doubles.
//
// HUMAN=1 switches to a club-player model: eyes and paddle one beat
// (~200ms of game time) behind the field, an incoming ball picked by
// ear rather than by nearest when several are in the air, no edge-hit
// hunting, and a wide deadzone on every correction. THE 60% BALANCE
// TARGET IS CALIBRATED AGAINST THIS PLAYER, not the ceiling one: a
// human is not flawless, and tuning to the ceiling would promise the
// real player odds the game never delivers. The balance line does the
// skill-normalizing on its own (it reads the player's own score against
// the 60/40 expectation, so a weaker player gets leaned on harder);
// what the harness answers is whether the terms bracket a club player
// around that line, and where the flawless ceiling tops out against a
// machine playing its best.
//
// Balance record against the 60% line, measured with the final knobs
// (baseAimWobble 34, gapAimStep 14, aim bracket 14..90 px, reach stretch
// 16 px/point capped 80, hot serve from 2 short at 2 px/point, gapSpeedStep
// 0.55, machineHitScale 0.83): the club player takes 0.565 of the points
// (0.570 over 20 matches and 0.562 over 15 more, ~700 points) — and that
// equilibrium holds +/- 0.02 whatever width the catch-up bracket is given.
// Opening the bracket wider saturates the deep-gap help and only lifts the
// flawless ceiling, which runs 0.70-0.72 on these knobs (176:67): the
// machine at its best can never pin a flawless player under about seven
// points in ten, and the club model's remaining losses are structural —
// attention split under multi-ball bunches, which one paddle cannot cover.
// The real player sits between the two models, and the line logic leans
// anyone back toward 0.60 the moment they drift past it: matches end knife-
// edge (11-8, 11-9, 11-10, and the odd 8-11 loss in the narrow-bracket
// rounds) at every skill level. Earlier bracket widths measured club
// 0.49-0.54, perfect 0.56-0.77 — the spread that settled on this one.
// Older-era proxy numbers, pre-line, kept for history: machine 4.6 and 6.3
// points a match (first to 11; loser-serves + hot catch-up serve, serve
// standby, chaos ball every 15 strokes, machine strokes at machineHitScale).

ShellRoot {
  id: testRoot

  Game {
    id: game

    width: 900
    height: 600
    active: true

    onEscapeRequested: {}
  }

  property int matches: 0
  property int targetMatches: Number(Quickshell.env("MATCHES") || 10)

  // Points won by each side across the whole run: the player's share of
  // these is the rally-odds measurement BALANCE reports.
  property int ptsP: 0
  property int ptsA: 0

  // Rally measurement: every ball moves every frame, so any change in the
  // weighted position sum marks a game frame. The weight keeps mirrored
  // balls from cancelling each other out mid-frame.
  property real prevBallSum: -999999
  property int frames: 0
  property int maxHits: 0
  property int outs: 0
  property int lastP: 0
  property int lastA: 0

  // Bot aim variety: re-rolled whenever a different ball takes focus.
  property real bias: 1
  property var prevChase: null

  // Human-model mode: the picture is only re-seen every `humanBeat` game
  // frames (~12 frames, a fifth of a second); between sightings the
  // paddle keeps working from the last snapshot, wobble and all.
  property bool human: Quickshell.env("HUMAN") === "1"
  property int humanBeat: 0
  property real humanTarget: 300

  function fastForward() {
    for (var i = 0; i < game.data.length; i += 1) {
      var o = game.data[i]
      if (o && o.interval === 16 && o.repeat === true) {
        o.interval = 2
        console.log("FF timer found")
      }
    }
  }

  Component.onCompleted: Qt.callLater(testRoot.fastForward)

  function logRally() {
    if (testRoot.frames <= 0)
      return
    console.log("RALLY hits=" + testRoot.maxHits
      + " outs=" + testRoot.outs
      + " rally_sec=" + (testRoot.frames * 16 / 1000).toFixed(1))
    testRoot.frames = 0
    testRoot.maxHits = 0
    testRoot.outs = 0
  }

  function botTick() {
    if (game.gameOver) {
      logRally()   // the match-ending rally never reaches a pause; log it here
      console.log("RESULT " + game.playerScore + " - " + game.aiScore)
      ptsP += game.playerScore
      ptsA += game.aiScore
      matches += 1
      if (matches >= targetMatches) {
        botTimer.stop()
        console.log("BALANCE mode=" + (testRoot.human ? "human" : "perfect")
          + " share=" + (ptsP / Math.max(1, ptsP + ptsA)).toFixed(3)
          + " points=" + ptsP + ":" + ptsA
          + " matches=" + matches
          + " machine_avg=" + (ptsA / matches).toFixed(1))
        console.log("ALLDONE")
        return
      }
      game.restartGame()
      testRoot.lastP = 0
      testRoot.lastA = 0
      return
    }
    if (game.paused) {
      // A fresh summon parks behind the pause card: release it. If the
      // player holds the opening serve, resuming also fires it — the
      // harness treats that as one beat and serves from the paddle's
      // resting spot.
      game.togglePause()
      return
    }
    if (game.waitingToServe) {
      // The last ball of a rally just left play: report the whole rally,
      // then put the next serve in play at once (serveNow is a no-op when
      // the machine holds the serve — it fires on its own).
      logRally()
      game.serveNow()
      return
    }

    var sum = 0
    for (var i = 0; i < game.balls.length; i += 1)
      sum += game.balls[i].posX + 13.37 * game.balls[i].posY
    if (sum !== testRoot.prevBallSum)
      testRoot.frames += 1
    testRoot.prevBallSum = sum

    if (game.rallyCount > testRoot.maxHits)
      testRoot.maxHits = game.rallyCount

    if (game.playerScore !== testRoot.lastP || game.aiScore !== testRoot.lastA) {
      testRoot.outs += (game.playerScore - testRoot.lastP)
        + (game.aiScore - testRoot.lastA)
      testRoot.lastP = game.playerScore
      testRoot.lastA = game.aiScore
      console.log("BALLOUT p=" + testRoot.lastP + " a=" + testRoot.lastA
        + " balls=" + game.balls.length)
    }

    // Flawless play on the ball that arrives first: of the balls coming at
    // the paddle, chase the nearest, and put an edge hit on it for a steep
    // angle. One paddle cannot be everywhere at once once the chaos balls
    // are out — that is the point of the rule.
    var chase = null
    var target
    if (testRoot.human) {
      // Club-player play: the field is re-seen a beat late, and when
      // several balls bear down, eyes land on one of them at random
      // rather than the nearest — attention splits. What the paddle
      // chases is that last snapshot plus a small aiming wobble of its
      // own; every correction overshoots or falls short a little.
      if (testRoot.humanBeat <= 0) {
        testRoot.humanBeat = 12
        var pool = []
        for (var p = 0; p < game.balls.length; p += 1) {
          if (game.balls[p].velX < 0)
            pool.push(game.balls[p])
        }
        if (pool.length === 1) {
          // One ball coming: a club player tracks it clean, a touch
          // late and a hair off — small error, no wild swings.
          testRoot.humanTarget = pool[0].posY + (Math.random() * 2 - 1) * 12
        } else if (pool.length > 1) {
          // Several coming: attention splits, eyes land on one at
          // random rather than the nearest, and the aim is looser.
          var pick = pool[Math.floor(Math.random() * pool.length)]
          testRoot.humanTarget = pick.posY + (Math.random() * 2 - 1) * 30
        } else {
          testRoot.humanTarget = game.height / 2 + (Math.random() * 2 - 1) * 20
        }
      }
      testRoot.humanBeat -= 1
      target = testRoot.humanTarget
    } else {
      for (var j = 0; j < game.balls.length; j += 1) {
        var b = game.balls[j]
        if (b.velX < 0 && (chase === null || b.posX < chase.posX))
          chase = b
      }

      if (chase !== null) {
        if (chase !== testRoot.prevChase)
          bias = Math.random() < 0.5 ? -1 : 1   // new ball in focus: vary angle
        testRoot.prevChase = chase
        target = chase.posY + bias * 45
      } else {
        testRoot.prevChase = null
        target = game.height / 2
      }
    }

    var dead = testRoot.human ? 10 : 4
    game.upPressed = game.playerCenterY > target + dead
    game.downPressed = game.playerCenterY < target - dead
  }

  Timer {
    id: botTimer

    // Polls faster than the 2ms fast-forwarded game step, so the frame
    // counter below can never miss a move between polls.
    interval: 1
    repeat: true
    triggeredOnStart: true
    running: true
    onTriggered: testRoot.botTick()
  }
}
