# Omapong

Classic Pong style game with a few twists made specifically for Omarchy Linux
and Quickshell, fully implemented in QML. It ships as an Omarchy bar widget:
click the `▮•▮` mark in the bar and the game window opens.

```
╔══════════════════════════════════════════════════╗
║           ╭───────────────────────────╮          ║
║           │  3        27        2     │          ║
║ ▓         │  you     rally      ai    │        ▓ ║
║ ▓                     ●               │        ▓ ║
║ ▓                                     │        ▓ ║
║           ╰───────────────────────────╯          ║
║ spacebar - serve/pause, w/s - move paddle        ║
╚══════════════════════════════════════════════════╝
```

## Install

```bash
omarchy plugin enable io.github.jeffsauer.omapong --section center
```

## Playing

The linux username is used for the human player name, and is on the left.
The system hostname is used for the computer player name, and is on the right.

The gane plays like the classic Pong game... with a few twists. Starts off slow
and steady, the speed of the ball gradually increases.  On every multiple of 15
hits during a rally, an additional fresh ball is added into play, up to six total.
The round ends when no balls are left in play.  The first player to win 11
rounds wins the match.

| Input | Action |
|---|---|
| `W` / `S` | move the left player paddle up or down |
| `Space` | serves the ball, pauses / resumes a rally |
| Mouse Click | pause / resume |
| `M` | mute / unmute sound effects |
| `Escape` | mid-round, raises a confirmation dialog to quit the game |

## Competitive Game Logic

The machine tracks the ball near-exactly, so the round is rubber-banded to
keep it competitive — and the rubber band now keys on a balance line, not the
raw score. The line is the share of the points the game hands you by design:
60%. Every catch-up term reads your distance from that line. Short of it,
your paddle moves faster and visibly stretches (capped at 80 px), the
machine's aim error — re-rolled at every stroke you play, and growing with
the length of the rally — eventually makes it miss, and its paddle loses
speed. The machine also swings softer than you: its returns leave the paddle
at 83% your speed, slower and flatter, so a crowded field stays cover-able.

Fall two points short of the line and the catch-up grows: your serve also
leaves your paddle hotter — the other side gets far less time to set up its
return. Get past the line, though, and the same terms turn on you: the
machine tracks tighter, chases quicker, and hot serves come against you, so
a lead is earned every point of the way and never rides out on autopilot.
The net effect is the point: on any given point you win roughly six in ten,
whatever the scoreboard says — a struggling player gets nudged back into the
round, and a runaway leader meets the machine at its best. Rally durations were
targeted to average about one minute, and two things force the eventual
miss — the aim wobble, and the extra balls that pile up past stroke fifteen
until whoever is playing worse simply cannot cover every line at once. A
rally always resolves rather than grinding on forever.

The ball has three voices: a ping off either paddle, a low thud off the top
or bottom wall, and a whoosh when a ball slips past either paddle — both
sides' misses sound the same. The game always opens muted, and `M` unmutes
or mutes at any time; the bottom status bar shows which state you are in.

## Layout

| File | Role |
|---|---|
| `manifest.json` | plugin contract: kind `bar-widget`, entry point, bar metadata |
| `BarWidget.qml` | the bar button; hosts `Panel.qml` in an always-alive `visible: false` Loader and forwards `open`/`close`/`toggle`/`closeForPopoutSwitch` to it |
| `Panel.qml` | the popout itself: a `qs.Ui` `KeyboardPanel` card anchored to the bar button, centred under the bar, hosting `Game.qml` |
| `Game.qml` | the playfield, input, and game logic |
| `sounds/` | the three sound effects (ping, thud, whoosh), generated with ffmpeg |
| `dev.qml` | standalone harness for working on the game without touching the shell |
| `test.qml` | windowless balance harness: runs the real game logic headless with an embedded perfect-play bot (its header documents how to run it) |
| `omapong.qml` | the original single-file standalone app, kept for reference |

The Loader in `BarWidget.qml` keeps the panel instance — and a round in
progress — alive between showings, so reopening paints the game exactly where
the last click interrupted it, behind the click-to-continue card. The game
loop only runs while the panel is open.

Colours come from `qs.Commons.Color`, so the game takes the current Omarchy
theme the moment it changes; nothing to re-theme per game. Small label text —
names, the rally counter, the status line, card lines — keeps the theme's
muted tone until that tone sits too close to its surface to read: `Balance.js`
measures the WCAG contrast and walks the colour toward the theme's foreground
(or, on a light theme whose whole palette is too soft against the shaded
plate, toward black/white) until it clears a contrast floor — 6.0 for the
fine print, 5.5 for the big rally digits, 5.0 for names. Decorative pieces —
court lines, borders, the serve ghost — stay plain muted.

## How the popout works

Everything about opening, placing, and dismissing the game comes from
`qs.Ui`'s `KeyboardPanel`, the same part Omarchy's own bar popups are built
on. No Hyprland window rules are involved: the card is a layer-shell overlay
hung from the bar strip, centred under the bar with `centerOnBar: true`, and
it slides open like the built-in popouts.

- **Dismissal is pointer-only.** A real mouse click anywhere outside the card
  lands on the overlay and closes the panel (transparent twin overlays catch
  the click on the other monitors, because the compositor hit-tests pointer
  input per output). A click on another bar icon swaps popouts in one click.
- **Focus loss never dismisses.** When focus wanders off on its own — you alt
  into a browser, say — the panel stays put; the game's input layer just sees
  its active focus drop and holds the round paused. Only a click sends the
  game away.
- **Keyboard focus.** `KeyboardPanel` primes the surface onto the keyboard
  (`WlrKeyboardFocus.Exclusive` for 75 ms, then `OnDemand`) and calls
  `forceActiveFocus` on `focusTarget`. The target must be the item that
  carries the `Keys` handlers — which here is `Game.qml`'s input layer,
  exposed as `game.inputTarget`. Pointing `focusTarget` at the `Game` root
  instead silently swallows every key: the root takes the focus, has no
  handlers, and the `inputLayer` child never sees anything.

## Development

Run the real `Panel.qml` outside the shell:

```bash
QML_IMPORT_PATH=/usr/share/omarchy/shell qs -c dev.qml
```

`qs.Commons` and `qs.Ui` live under `/usr/share/omarchy/shell`, hence the
import path.

Drive the installed copy over IPC:

```bash
omarchy-shell shell toggle io.github.jeffsauer.omapong '{}'
omarchy-shell shell hide   io.github.jeffsauer.omapong
```

