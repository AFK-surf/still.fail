// A new chat on a narrow phone, what it runs on as crowded as a person's phone showed it (newchat_fixture.mbt
// newchat-crowded, 2026-10-26): the station's and the model's controls over the composer, the frequent combinations,
// the model's panel; each of their words whole, on one line, in the window.

///|
/// A phone as narrow as most get (`w` across), newchat-crowded's page (`mode`) risen over it.
fn crowded(mode : String, w? : Double = crowded_w) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h=crowded_h, platform=2)
  open_mode(mode)
  t.draw()
  t.run_for(@ui.nav_rise_ms)
  t
}

///|
let crowded_w : Double = 360.0

///|
let crowded_h : Double = 780.0

///|
/// The narrowest phones (320 across: as narrow as a 349 one with its words 15% bigger, the person's of 2026-10-26).
let crowded_narrowest : Double = 320.0

///|
/// Narrower than phones are, the station's control and the model's not both whole there.
let crowded_cramped : Double = 280.0

///|
/// The lines of words drawn in (x, y, w, h).
fn runs_in(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Array[@ui.TextRun] {
  let (x, y, w, h) = r
  t.text_runs().filter(fn(run) { run.base > y && run.base < y + h && run.x1 > x && run.x0 < x + w })
}

///|
test "narrow: the station's control says its name whole beside the model's, which leaves out what has not the room and keeps none empty" {
  let t = crowded("newchat-crowded", w=crowded_narrowest)
  // its name, all of it (not 「Stu…」)
  assert_true(t.text_runs().iter().any(fn(r) { r.text == "Studio" }), msg="\{t.text_runs().map(fn(r) { r.text })}")
  // the two glass controls over the composer, side by side in the window
  let glass = t.boxes().filter(fn(b) { b.glass && b.kind == "row" && (b.h - 30.0).abs() < 0.5 })
  assert_eq(glass.length(), 2, msg="\{t.boxes().filter(fn(b) { b.glass }).map(fn(b) { (b.kind, b.x, b.y, b.w, b.h) })}")
  let (station, model) = (glass[0], glass[1])
  assert_true(station.x + station.w <= model.x)
  assert_true(model.x + model.w <= crowded_narrowest)
  // the model's: as wide as what it keeps (its padding past the last of it, no more)
  let kept = t
    .boxes()
    .filter(fn(b) { b.parent == model.index && b.opacity > 0.0 && b.w > 0.0 })
    .fold(init=0.0, fn(m, b) { if b.x + b.w > m { b.x + b.w } else { m } })
  assert_true(model.x + model.w - kept <= 12.5, msg="\{model.x + model.w - kept} past what it keeps")
  // what it keeps of itself: the model's name, whole
  assert_true(runs_in(t, (model.x, model.y, model.w, model.h)).iter().any(fn(r) { r.text == "DeepSeek V4.1 Flash" }))
}

///|
test "narrower still: the station's name leaves its control whole after what the model's leaves, the model's name stays" {
  let t = crowded("newchat-crowded", w=crowded_cramped)
  let glass = t.boxes().filter(fn(b) { b.glass && b.kind == "row" && (b.h - 30.0).abs() < 0.5 })
  assert_eq(glass.length(), 2)
  let (station, model) = (glass[0], glass[1])
  assert_true(model.x + model.w <= crowded_cramped)
  let station_words = runs_in(t, (station.x, station.y, station.w, station.h))
  // no part of its name (not 「Stu…」): its mark and its chevron (the page says where it starts)
  assert_true(station_words.length() == 0, msg="\{station_words.map(fn(r) { r.text })}")
  assert_true(runs_in(t, (model.x, model.y, model.w, model.h)).iter().any(fn(r) { r.text == "DeepSeek V4.1 Flash" }))
  // nothing past what it keeps
  let kept = t
    .boxes()
    .filter(fn(b) { b.parent == model.index && b.opacity > 0.0 && b.w > 0.0 })
    .fold(init=0.0, fn(m, b) { if b.x + b.w > m { b.x + b.w } else { m } })
  assert_true(model.x + model.w - kept <= 12.5)
}

///|
test "narrow: each frequent combination on one line in the window, a long one leaving its runtime out" {
  let t = crowded("newchat-crowded")
  let chips = []
  for label in ["GPT-6 Astra · 中", "DeepSeek V4.1 Flash · DeepSeek Harness · 高", "SWE-2 · 高"] {
    chips.push(t.get(Button, label~))
  }
  for chip in chips {
    let (x, _, w, _) = chip.rect
    assert_true(x >= 0.0 && x + w <= crowded_w, msg="\{chip.label} \{chip.rect}")
    let runs = runs_in(t, chip.rect)
    assert_true(runs.length() > 0)
    for r in runs {
      assert_true(r.base == runs[0].base, msg="\{chip.label} on more than one line")
      assert_true(r.x0 >= x && r.x1 <= x + w, msg="\{r.text} past \{chip.label}")
    }
  }
  // the model always, how hard it thinks always
  let words = runs_in(t, chips[1].rect).map(fn(r) { r.text })
  assert_true(words.contains("DeepSeek V4.1 Flash"))
  assert_true(words.contains("高"))
}

///|
/// Whether words `name` are laid out whole (as wide as they advance, none cut short) inside `r` across.
fn whole_in(t : @ui.Tester, name : String, r : (Double, Double, Double, Double)) -> Bool {
  let (x, _, w, _) = r
  t
  .boxes()
  .iter()
  .any(fn(b) {
    b.kind == "text" &&
    b.text == name &&
    b.x >= x - 0.5 &&
    b.x + b.w <= x + w + 0.5 &&
    b.w >= @ui.text_advance(name, size=b.font_size, weight=b.weight) - 0.5
  })
}

///|
test "narrow: the model's panel lays the runtimes and how hard it thinks under the models, every name whole, the sheet as tall as its most" {
  let t = crowded("newchat-crowded-model")
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Dialog).rect
  let (_, _, _, sh) = sheet
  // more than the window has room for: the sheet as tall as its most, scrolling as one
  assert_true((sh - crowded_h * @sf.sheet_most).abs() < 1.0, msg="the sheet is \{sh} high")
  // the models, the runtimes, how hard it thinks: their rows in the sheet, their names whole in them
  let names = [
    "Opus 5.5", "GPT-6 Astra", "DeepSeek V4.1 Flash", "Grok 4.7 Build Fast", "Kimi For Coding", "SWE-2", "Claude Code",
    "Codex", "DeepSeek Harness", "默认", "高",
  ]
  for name in names {
    let row = t.get(Button, label=name).rect
    assert_true(row.0 >= sheet.0 && row.0 + row.2 <= sheet.0 + sheet.2, msg="\{name}: \{row} out of \{sheet}")
    assert_true(whole_in(t, name, row), msg="\{name} not whole in its row")
  }
  // the runtimes and how hard it thinks under the models (the last of them over them)
  let swe = t.get(Button, label="SWE-2").rect
  for name in ["Claude Code", "DeepSeek Harness", "默认", "高"] {
    assert_true(t.get(Button, label=name).rect.1 > swe.1, msg="\{name} not under the models")
  }
}

///|
test "wide: the model's panel beside its control has the models, the runtimes and how hard it thinks side by side" {
  let src = fixture_app("newchat-crowded-model")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  let model = t.get(Button, label="DeepSeek V4.1 Flash").rect
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  let effort = t.get(Button, label="高").rect
  assert_true(runtime.0 > model.0 + model.2, msg="\{model} \{runtime}")
  assert_true(effort.0 > runtime.0 + runtime.2, msg="\{runtime} \{effort}")
}
