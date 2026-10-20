// The compact bar (@sf.nav_bar) on settings' pages that have one: back, the title and what is at its end centred on
// the bar's one 32 line, their boxes' middles (as laid out, not their letters') within 0.5 of each other.

///|
test "nav bar: back, title and what is at its end on one line (settings' pages)" {
  for mode in [
    "settings-usage", "settings-archive", "settings-connects", "settings-memory", "settings-memory-doc", "settings-profile",
    "settings-profiles", "settings-station", "settings-stations",
  ] {
    reset()
    @settings.reset()
    let src = fixture(mode)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
    open_setting(@settings.fixture_page(mode))
    t.draw()
    t.run_for(@ui.nav_push_ms)
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
