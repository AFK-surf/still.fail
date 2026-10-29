// A new chat on a narrow phone, what it runs on as crowded as a person's phone showed it (newchat_fixture.mbt
// newchat-crowded, 2026-10-26): the station's and the model's controls over the composer, the frequent combinations,
// the model's panel; each of their words whole, on one line, in the window.

///|
/// A phone as narrow as most get (`w` across), newchat-crowded's page (`mode`) risen over it.
fn crowded(mode : String, w? : Double = crowded_w, h? : Double = crowded_h) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=2)
  open_mode(mode)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
let crowded_w : Double = 360.0

///|
let crowded_h : Double = 780.0

///|
/// A phone's window too short for all of the crowded model's panel.
let crowded_short : Double = 600.0

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
/// The rectangle of the words `name` drawn in the sheet (`sheet`), whole (as wide as they advance).
fn words_whole(t : @ui.Tester, name : String, sheet : (Double, Double, Double, Double)) -> (Double, Double, Double, Double)? {
  let (sx, sy, sw, sh) = sheet
  t
  .boxes()
  .iter()
  .find_first(fn(b) {
    b.kind == "text" &&
    b.text == name &&
    b.y >= sy &&
    b.y < sy + sh &&
    b.x >= sx &&
    b.x + b.w <= sx + sw + 0.5 &&
    b.w >= @ui.text_advance(name, size=b.font_size, weight=b.weight) - 0.5
  })
  .map(fn(b) { (b.x, b.y, b.w, b.h) })
}

///|
test "narrow: the model's panel has the models across it, every name whole, the runtime and how hard it thinks as selects under them in view as they scroll" {
  // (a window too short for all of it)
  let t = crowded("newchat-crowded-model", h=crowded_short)
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Dialog).rect
  let (_, _, _, sh) = sheet
  // more than the window has room for: the sheet as tall as its most
  assert_true((sh - crowded_short * @sf.sheet_most).abs() < 1.0, msg="the sheet is \{sh} high")
  // the models' names whole
  for name in ["Opus 5.5", "GPT-6 Astra", "DeepSeek V4.1 Flash", "Grok 4.7 Build Fast"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole in the sheet")
  }
  // the runtime and how hard it thinks: selects side by side under the models, their words whole, in the sheet
  let runtime = t.get(Button, label="运行时: DeepSeek Harness").rect
  let effort = t.get(Button, label="思考深度: 高").rect
  let model = t.get(Button, label="Opus 5.5").rect
  assert_true(runtime.1 > model.1 && (runtime.1 - effort.1).abs() < 0.5 && effort.0 > runtime.0 + runtime.2)
  assert_true(runtime.1 + runtime.3 <= sheet.1 + sh && effort.0 + effort.2 <= sheet.0 + sheet.2)
  assert_true(words_whole(t, "DeepSeek Harness", sheet) is Some(_), msg="DeepSeek Harness not whole")
  // the models scrolled: the selects where they were
  let mx = model.0 + model.2 / 2.0
  t.drag(mx, runtime.1 - 40.0, mx, model.1 + 40.0)
  t.run_for(@kit.presence_in_ms)
  assert_true(t.get(Button, label="运行时: DeepSeek Harness").rect == runtime, msg="the runtime moved with the models")
  assert_true(t.get(Button, label="思考深度: 高").rect == effort, msg="how hard it thinks moved with the models")
  assert_true(t.get(Button, label="Opus 5.5").rect.1 < model.1, msg="the models did not scroll")
}

///|
test "narrow, few models: the same panel, its one runtime's select not to be pressed" {
  let t = crowded("newchat-model")
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Dialog).rect
  let model = t.get(Button, label="GPT-6").rect
  let runtime = t.get(Button, label="运行时: Claude Code")
  assert_true(runtime.disabled)
  assert_true(runtime.rect.1 > model.1)
  assert_true(t.get(Button, label="思考深度: 高").rect.1 > model.1)
  for name in ["Opus 5.5", "Sonnet 5", "GPT-6", "Claude Code", "高"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole in the sheet")
  }
}

///|
test "wide: the model's panel beside its control has room for all three columns: the models, the runtimes, how hard it thinks side by side" {
  let src = fixture_app("newchat-crowded-model")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  let model = t.get(Button, label="DeepSeek V4.1 Flash").rect
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  let effort = t.get(Button, label="高").rect
  assert_true(runtime.0 > model.0 + model.2, msg="\{model} \{runtime}")
  assert_true(effort.0 > runtime.0 + runtime.2, msg="\{runtime} \{effort}")
  // (no selects for them: they are not said twice)
  assert_true(t.query(Button, label="运行时: DeepSeek Harness") is None)
}
