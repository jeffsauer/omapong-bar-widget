// Contrast helpers for the game's small label text.
//
// The theme's muted colour is usually a dim tone (often the terminal's
// color8), and on some themes it sits closer to the court's surface than
// the names, rally counter, and status line need. labelColor answers with
// the first step up a contrast ladder that clears a WCAG contrast ratio
// against the surface the label actually sits on, so a label keeps its
// theme tone until reading it would be a struggle.

function srgbLuma(r, g, b) {
  function chan(v) {
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
  }

  return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b)
}

// WCAG relative-contrast ratio between two colours, 1..21.
function contrast(a, b) {
  var la = srgbLuma(a.r, a.g, a.b)
  var lb = srgbLuma(b.r, b.g, b.b)
  var hi = Math.max(la, lb)
  var lo = Math.min(la, lb)
  return (hi + 0.05) / (lo + 0.05)
}

// The legible extreme for a surface: whichever of black or white reads
// hardest against it. Light themes can ship a muted *and* a foreground
// that both sit too close to the game's shaded surfaces, so the ladder
// needs an end beyond the palette that always clears.
function legibleEnd(background) {
  return contrast(Qt.rgba(0, 0, 0, 1.0), background)
    >= contrast(Qt.rgba(1, 1, 1, 1.0), background)
    ? Qt.rgba(0, 0, 0, 1.0) : Qt.rgba(1, 1, 1, 1.0)
}

// Walk from base toward goal — and on to the legible extreme when goal
// itself is too weak for this surface — and return the first blend whose
// contrast against background clears `want`; the legible extreme if even
// that never clears (the best there is).
function labelColor(base, goal, background, want) {
  var end = legibleEnd(background)
  if (contrast(goal, background) < contrast(end, background))
    goal = end
  var steps = 48
  for (var i = 0; i <= steps; i = i + 1) {
    var t = i / steps
    var c = Qt.rgba(base.r + (goal.r - base.r) * t,
      base.g + (goal.g - base.g) * t,
      base.b + (goal.b - base.b) * t, 1.0)
    if (contrast(c, background) >= want)
      return c
  }
  return end
}
