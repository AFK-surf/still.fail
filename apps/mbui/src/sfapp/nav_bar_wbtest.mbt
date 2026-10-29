// The compact bar (@sf.nav_bar) on settings' pages that have one: back, the title and what is at its end centred on
// the bar's one 32 line, their boxes' middles (as laid out, not their letters') within 0.5 of each other.

///|
test "nav bar: back, title and what is at its end on one line (settings' pages)" {
  for mode in [
    "settings-archive",
    "settings-profiles", "settings-stations", "settings-new-profile", "settings-run-models",
  ] {
    reset()
    @settings.reset()
    let src = fixture(mode)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
    open_setting(@settings.fixture_page(mode))
    t.draw()
    t.run_for(@ui.move_most_ms)
    // what the bar's line holds: what is seen on it, no taller than it (the line under a title is lower)
    let mids : Array[(String, Double)] = []
    for s in t.semantics() {
      let (_, y, _, h) = s.rect
      if !s.hidden && h > 0.0 && h <= 34.0 && y >= 0.0 && y + h / 2.0 < 38.0 {
        mids.push((s.label, y + h / 2.0))
      }
    }
    let mut lo = 1000.0
    let mut hi = -1000.0
    for m in mids {
      lo = if m.1 < lo { m.1 } else { lo }
      hi = if m.1 > hi { m.1 } else { hi }
    }
    let said = mids.map(fn(m) { m.0 + "@" + m.1.to_string() }).join(", ")
    println("nav bar \{mode}: \{said}")
    if mids.length() < 2 || hi - lo > 0.5 {
      fail("\{mode}: the bar's line holds \{said}")
    }
  }
}

///|
/// Where the top bar's back and title are on settings' `mode` with the status bar `top` high: what is seen in the band
/// the bar's 32 line takes under it (labels, their boxes' middles).
fn bar_line_under(mode : String, top : Double) -> Array[(String, Double)] {
  reset()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  open_setting(@settings.fixture_page(mode))
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":\{top},\"bottom\":0,\"left\":0,\"right\":0}}")
  t.draw()
  t.run_for(@ui.move_most_ms)
  let mids : Array[(String, Double)] = []
  for s in t.semantics() {
    let (_, y, _, h) = s.rect
    if !s.hidden && h > 0.0 && h <= 34.0 && y + h / 2.0 < top + 38.0 {
      mids.push((s.label, y + h / 2.0))
    }
  }
  mids
}

///|
test "nav bar: under the status bar on the pages that go back a step of their own (the new profile's, a connect's, a run's lists)" {
  for mode in ["settings-new-profile", "settings-run-models"] {
    let mids = bar_line_under(mode, 24.0)
    let said = mids.map(fn(m) { m.0 + "@" + m.1.to_string() }).join(", ")
    println("under a 24 status bar \{mode}: \{said}")
    // back and the title, both below the status bar (the page's paper is drawn over it), on one line
    if mids.length() < 2 || mids.iter().any(fn(m) { m.1 < 24.0 }) {
      fail("\{mode}: the bar's line under a 24 status bar holds \{said}")
    }
  }
}
