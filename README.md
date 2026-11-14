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

Copy the plugin's own files into the shell's plugin directory and enable it:

```bash
./sync.sh                                    # rsync + validate + reloadPlugins
omarchy plugin enable io.github.jeffsauer.omapong --section right
```

A symlink is deliberately not used: `omarchy plugin validate` rejects a
symlinked plugin folder, and a plain copy is what a published third-party
plugin ships as anyway. `sync.sh` installs only the plugin's own files — the
development harness, the original standalone game, and this README stay here.

The shell watches this directory and reloads a saved plugin immediately. If an
edit ever breaks a panel instance (an incubation error leaves the old one in
place), a plain reload won't recover it — restart the shell for real:

```bash
omarchy-restart-shell
```

## Playing

The game always opens (or reopens) paused behind a card, centered in the
court's lower half — the span between the centre line and the bottom line
— "click to begin" for a fresh round, "click to continue" for one waiting
mid-round. Click the playfield or press `Space` to start. On a fresh
summon the **OMAPONG** wordmark stands on the centre line, its baseline
right on the court's midline: a logo drawn as a grid of square pixel
cells — one line, sized up to the largest cell that fits the word
inside the court's width, and graded from a bright top row to a dark
baseline, all built off the live theme's foreground — the same blocky
terminal style as the omarchy.org wordmark, which is built from exactly
that kind of grid. It clears the moment the round begins — on the click
to begin, or on the first serve if a serve somehow lands first. A fresh
summon opens into serve standby: whoever holds the opening serve takes
it from there. The
paddles wait it out at the court's thirds — yours parked in the lower
third, the machine full-height in the pocket between the scoreboard
shelf and the wordmark — so nothing stands in front of the logo. The
opening serve marks out inside that same pocket.

| Input | Action |
|---|---|
| `W` / `S`, `Up` / `Down` | move the left paddle (also while positioning a serve) |
| `Space` | serve during standby (player's turn); pause / resume in a rally; restart after the round ends |
| Click | pause / resume (the game also pauses itself whenever it loses focus or is hidden away) |
| `R`, `Enter` | restart after the round ends |
| `M` | mute / unmute the sound effects |
| `Escape` | mid-round, raises an **"Abandon current game (Y/N)?"** prompt: `y` or **Yes** resets to a fresh game and closes the panel, `n` or **No** (or a second `Escape`) drops the question and keeps playing. Before the first serve, or once the round is over, it closes without asking — as does clicking the bar mark, which keeps the round where it was |

First to 11 points takes the round, and a rally ends only when the last
ball in play crosses an end line: after that the game holds the score and
goes to **serve standby** — no ball in play, both paddles free to move.
The loser of the rally that just ended — the side that conceded its
final ball — always serves next, and at the start of a match a random
side opens. A player serve is yours to place: a soft ghost ball pulses
against your paddle as you w/s to any height you like, and `Space`
launches the serve from exactly there. The machine does the same in its
own time: it picks a mark, walks its paddle there, settles a beat, and
fires without asking anyone. Ball,
paddle, and AI speed scale with the total score, and the ball speeds up
through a rally. The match is named for this machine: the scoreboard pairs your Linux
username with the system hostname, each name printed under its own score
inside a rounded scoreboard plate — hung 20px below the court's top line
and outlined in the same grid-line style — that keeps the centre line
from crossing the rally counter. All three numbers — both scores and the counter — sit on
one shared baseline. When either score changes, that number flares, and
the rally counter flares on every stroke: each gets a blurred halo of its
colour plus a small scale pop, one second long.

Rallies crowd up as they run. Every 15 strokes of a rally, a fresh ball
enters play at a random height on the centre line and leaves in a random
direction — and once more than one ball is live, the counter's label
underneath it says so (`rally · 3 balls`). A miss retires just its own
ball and scores a point; the rally carries on with whatever balls
survive, so one long rally can score several points at once, and a side
under pressure concedes them in bunches. Chaos tops out at six balls.

The machine tracks the ball near-exactly, so the round is rubber-banded to
keep it a contest — and the rubber band now keys on a balance line, not the
raw score. The line is the share of the points the game hands you by design:
60%. Every catch-up term reads your distance from that line. Short of it,
your paddle moves faster and visibly stretches (capped at 80 px), the
machine's aim error — re-rolled at every stroke you play, and growing with
the length of the rally — eventually makes it miss, and its paddle loses
speed. The machine also swings softer than you: its returns leave the paddle
at 83% your speed, slower and flatter, so a crowded field stays coverable.
Fall two points short of the line and the catch-up grows: your serve also
leaves your paddle hotter — the other side gets far less time to set up its
return. Get past the line, though, and the same terms turn on you: the
machine tracks tighter, chases quicker, and hot serves come against you, so
a lead is earned every point of the way and never rides out on autopilot.
The net effect is the point: on any given point you win roughly six in ten,
whatever the scoreboard says — a struggling player gets nudged back into the
round, and a runaway leader meets the machine at its best. Measured across
hundreds of points, a solid-but-human player lands near five and a half to
six in ten, and even flawless play tops out near seven — the catch-up keeps
a paddle's worth of cover in reserve for whoever needs it. Rallies are
paced to build: they run about a minute, and two things force the eventual
miss — the aim wobble, and the extra balls that pile up past stroke fifteen
until whoever is playing worse simply cannot cover every line at once. A
rally always resolves rather than grinding on forever.

The ball has three voices: a ping off either paddle, a low thud off the top
or bottom wall, and a whoosh when a ball slips past either paddle — both
sides' misses sound the same. The game always opens muted — it pops out of
the bar uninvited — and `M` unmutes or mutes at any time; the field's
bottom bar shows which state you are in.

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

## Original licence notes

Game logic and tuning constants carried over unchanged from `omapong.qml`.
