// The compact bar (@sf.nav_bar) on settings' pages that have one: back, the title and what is at its end centred on
// the bar's one 32 line, their boxes' middles (as laid out, not their letters') within 0.5 of each other. A page made
// once has the frame's standard head instead (page_node's): back, and what is at its end, on that line the same way,
// its large title under the line.

///|
/// Whether settings' `mode` opens a page with the frame's standard head (page_node's: back on the line, the large
/// title under it), with that title; else a compact bar of its own (its title on the line).
fn standard_head(mode : String) -> String? {
  match mode {
    "settings-new-profile" => Some("选择服务商")
    _ => None
  }
}

///|
test "nav bar: back, title and what is at its end on one line (settings' pages)" {
  for mode in [
    "settings-archive",
    "settings-profiles", "settings-stations", "settings-new-profile", "settings-run-models",
  ] {
    new_run()
    @settings.reset()
    let src = fixture(mode)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
    match standard_head(mode) {
      // the standard head: back on the line (and what is at its end, as one), the large title under the line
      Some(title) => {
        if mids.length() < 1 || hi - lo > 0.25 || !mids.iter().any(fn(m) { m.0.contains("设置") }) {
          fail("\{mode}: the head's line holds \{said}")
        }
        match t.find(title) {
          Some((_, y)) if y > hi + 16.0 => ()
          at => fail("\{mode}: its title \{title} at \{Repr(at)}, the head's line at \{hi}")
        }
      }
      None =>
        if mids.length() < 2 || hi - lo > 0.25 {
          fail("\{mode}: the bar's line holds \{said}")
        }
    }
  }
}

///|
/// Where the top bar's back and title are on settings' `mode` with the status bar `top` high: what is seen in the band
/// the bar's 32 line takes under it (labels, their boxes' middles).
fn bar_line_under(mode : String, top : Double) -> Array[(String, Double)] {
  new_run()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
    // back and the title, both below the status bar (the page's paper is drawn over it), on one line; a standard
    // head's back alone on it (its title under it, lower still)
    let least = if standard_head(mode) is Some(_) { 1 } else { 2 }
    let back_there = standard_head(mode) is None || mids.iter().any(fn(m) { m.0.contains("设置") })
    if mids.length() < least || !back_there || mids.iter().any(fn(m) { m.1 < 24.0 }) {
      fail("\{mode}: the bar's line under a 24 status bar holds \{said}")
    }
  }
}

///|
/// Where back's middle is on the head's line of settings' `mode` (its box's, as laid out: the first thing on the line
/// from the left), under a status bar `top` high, with its words.
fn back_middle(mode : String, top : Double) -> (String, Double)? {
  new_run()
  @settings.reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_setting(@settings.fixture_page(mode))
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":\{top},\"bottom\":0,\"left\":0,\"right\":0}}")
  t.draw()
  t.run_for(@ui.move_most_ms)
  let mut first : (String, Double, Double)? = None
  for s in t.semantics() {
    let (x, y, _, h) = s.rect
    if !s.hidden && h > 0.0 && h <= 34.0 && y >= top && y + h / 2.0 < top + 38.0 {
      match first {
        Some((_, fx, _)) if fx <= x => ()
        _ => first = Some((s.label, x, y + h / 2.0))
      }
    }
  }
  first.map(fn(f) { (f.0, f.2) })
}

///|
test "nav bar: the standard head's back on the same line on every page made once (the new profile's among them)" {
  for top in [0.0, 24.0] {
    let at : Array[(String, Double)] = []
    let missing : Array[String] = []
    // (the notifications' page left out: under a status bar its back is not on the head's line, on main too; its own
    // follow-up)
    for mode in ["settings-new-profile", "settings-changelog", "settings-vault-items", "settings-prices"] {
      match back_middle(mode, top) {
        Some((words, y)) => at.push((mode + " " + words, y))
        None => missing.push(mode)
      }
    }
    let said = at.map(fn(m) { m.0 + "@" + m.1.to_string() }).join(", ")
    println("standard head under \{top}: \{said}; none on the line: \{Repr(missing)}")
    if !missing.is_empty() {
      fail("no back on the head's line under a \{top} status bar: \{Repr(missing)}")
    }
    if at.iter().any(fn(m) { m.1 != at[0].1 }) {
      fail("the standard head's back not on one line under a \{top} status bar: \{said}")
    }
  }
}
