// A tone's ground (green_bg, red_bg, accent_bg…: a pill's, a mention's) seen on every ground of its palette, and its
// ink read on it (docs/ui-panels.md 对比度): 1.25 to 1 off what it lies on, as what is drawn to be seen; 4.5 to 1 for
// its words. Grounds fitted to the page alone, opaque, were 1.0 to 1.1 off a card in the dark (2026-10-27).

///|
test "tones: each tone's ground seen and its ink read on every ground of every palette" {
  let wrong : Array[String] = []
  for p in [("wide light", wide_light), ("wide dark", wide_dark), ("touch light", narrow_light), ("touch dark", narrow_dark)] {
    let (name, pal) = p
    let grounds = [
      ("page", pal.bg),
      ("canvas", pal.canvas),
      ("raised", pal.raised),
      ("sidebar", pal.sidebar),
      ("list", pal.list),
      ("selected", pal.selected),
      ("paper", pal.paper),
      ("card", pal.card),
      ("card2", pal.card2),
      ("chip", pal.chip),
    ]
    let tones = [
      ("green", pal.green_bg, pal.green_ink),
      ("blue", pal.blue_bg, pal.blue),
      ("amber", pal.amber_bg, pal.warn_ink),
      ("red", pal.red_bg, pal.red),
      ("accent", pal.accent_bg, pal.accent_text),
    ]
    for g in grounds {
      for tone in tones {
        let laid = over(g.1, tone.1)
        let seen = @ui.contrast_ratio(laid, g.1)
        let read = @ui.contrast_ratio(tone.2, laid)
        if seen < 1.25 {
          wrong.push("\{name}: \{tone.0}'s ground on the \{g.0} \{seen}:1, under 1.25")
        }
        if read < 4.5 {
          wrong.push("\{name}: \{tone.0}'s ink on its ground on the \{g.0} \{read}:1, under 4.5")
        }
      }
    }
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}
