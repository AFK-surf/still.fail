// A new chat on a narrow phone, what it runs on as crowded as a person's phone showed it (newchat_fixture.mbt
// newchat-crowded, 2026-10-26): the station's and the model's controls over the composer, the model's panel and
// the frequent combinations in it; each of their words whole, on one line, in the window.

///|
/// A phone as narrow as most get (`w` across), newchat-crowded's page (`mode`) risen over it.
fn crowded(mode : String, w? : Double = crowded_w, h? : Double = crowded_h) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=2)
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
let crowded_short : Double = 540.0

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
  // the three glass controls over the composer (where, the preset, what on), side by side in the window
  let glass = t.boxes().filter(fn(b) { b.glass && b.kind == "row" && (b.h - 30.0).abs() < 0.5 })
  assert_eq(glass.length(), 3, msg="\{t.boxes().filter(fn(b) { b.glass }).map(fn(b) { (b.kind, b.x, b.y, b.w, b.h) })}")
  let (station, model) = (glass[0], glass[2])
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
  assert_eq(glass.length(), 3)
  let (station, model) = (glass[0], glass[2])
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
test "narrow: the models used most nearest how hard it thinks, at the sheet's foot, each with how it runs on its line" {
  let t = crowded("newchat-crowded-model")
  run_to_sheet_rest(t)
  let (sx, _, sw, _) = t.get(@ui.Role::Dialog).rect
  let effort = t.get(Radio, label="高").rect
  // (a sheet risen from the screen's foot: what is used most lowest, the most used of all nearest how hard it thinks)
  let rows = ["Opus 5.5", "SWE-2", "DeepSeek V4.1 Flash", "GPT-6 Astra"].map(fn(l) { t.get(Button, label=l) })
  for i in 1..<rows.length() {
    assert_true(rows[i].rect.1 > rows[i - 1].rect.1, msg="\{rows[i - 1].label} \{rows[i].label}")
  }
  assert_true(rows[3].rect.1 < effort.1)
  for row in rows {
    let (x, _, w, _) = row.rect
    assert_true(x >= sx && x + w <= sx + sw + 0.5, msg="\{row.label} \{row.rect}")
  }
  // how each last ran after its name, on its line: GPT-6 Astra's 中; DeepSeek's, the runtime it runs on of three and how
  // hard it thinks, giving way to its name where the row is short (cut short, else left out: the text's widths differ
  // by machine)
  let runs_of = fn(r : (Double, Double, Double, Double)) {
    runs_in(t, r).filter(fn(w) { w.x0 >= r.0 && w.x1 <= r.0 + r.2 }).map(fn(w) { w.text })
  }
  assert_true(runs_of(rows[3].rect).contains("中"), msg="\{runs_of(rows[3].rect)}")
  let deep = runs_of(rows[2].rect)
  assert_true(deep.contains("DeepSeek V4.1 Flash"), msg="\{deep}")
  assert_true(deep.iter().all(fn(w) { w == "DeepSeek V4.1 Flash" || w.has_prefix("DeepSeek H") }), msg="\{deep}")
}

///|
test "narrow: no frequent combination left on the new chat's page" {
  let t = crowded("newchat-crowded")
  assert_true(t.query(Button, label="SWE-2 · 高") is None)
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
test "narrow: the model's panel has the models across it, every name whole, how hard it thinks and the runtime under them, in view as they scroll" {
  // (a window too short for all of it)
  let t = crowded("newchat-crowded-model", h=crowded_short)
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Role::Dialog).rect
  let (_, _, _, sh) = sheet
  // more than the window has room for: the sheet as tall as its most
  assert_true((sh - crowded_short * @sf.sheet_most).abs() < 1.0, msg="the sheet is \{sh} high")
  // the models' names whole
  for name in ["Opus 5.5", "GPT-6 Astra", "DeepSeek V4.1 Flash", "Grok 4.7 Build Fast"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole in the sheet")
  }
  // how hard it thinks, its levels on one line under the models; the runtime a pill under them, saying the one picked,
  // the others a pick away; their words whole, in the sheet
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  let effort = t.get(Radio, label="高").rect
  let model = t.get(Button, label="Opus 5.5").rect
  assert_true(effort.1 > model.1 && runtime.1 > effort.1 + effort.3, msg="\{model} \{effort} \{runtime}")
  assert_true(t.query(Radio, label="Claude Code") is None, msg="the runtimes not picked laid out")
  assert_true(t.get(Radio, label="默认").rect.1 == effort.1, msg="how hard it thinks not on one line")
  assert_true(runtime.1 + runtime.3 <= sheet.1 + sh && runtime.0 + runtime.2 <= sheet.0 + sheet.2)
  for name in ["DeepSeek Harness", "高", "最高"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole")
  }
  // the models scrolled: the choices where they were
  let mx = model.0 + model.2 / 2.0
  t.drag(mx, model.1 + 1.5 * model.3, mx, model.1 - model.3)
  t.run_for(@kit.presence_in_ms)
  assert_true(t.get(Button, label="DeepSeek Harness").rect == runtime, msg="the runtime moved with the models")
  assert_true(t.get(Radio, label="高").rect == effort, msg="how hard it thinks moved with the models")
  assert_true(t.get(Button, label="Opus 5.5").rect.1 < model.1, msg="the models did not scroll")
}

///|
test "narrow, few models: the same panel; one runtime, nothing to choose of it" {
  let t = crowded("newchat-model")
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Role::Dialog).rect
  let model = t.get(Button, label="GPT-6").rect
  assert_true(t.query(Button, label="Claude Code") is None)
  assert_true(t.get(Radio, label="高").rect.1 > model.1)
  for name in ["Opus 5.5", "Sonnet 5", "GPT-6", "默认", "高"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole in the sheet")
  }
}

///|
test "wide: the model's panel beside its control has the models, how hard it thinks under them, the runtime under that" {
  let src = fixture_app("newchat-crowded-model")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  // (the models used most nearest how it runs, the rest past them: whichever way it opened)
  let model = t.get(Button, label="Opus 5.5").rect
  let used = t.get(Button, label="SWE-2").rect
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  let effort = t.get(Radio, label="高").rect
  assert_true(in_line(model.1, used.1, effort.1), msg="\{model} \{used} \{effort}")
  assert_true(runtime.1 != effort.1, msg="\{effort} \{runtime}")
  // pressed, the runtimes in a pick
  t.click(Button, label="DeepSeek Harness")
  t.run_for(squeeze_opening)
  assert_true(t.boxes().iter().any(fn(b) { b.kind == "text" && b.text == "Claude Code" }), msg="no pick of the runtimes")
}

///|
test "wide: how hard it thinks along its line, from the model's own to the most" {
  let src = fixture_app("newchat-crowded-model")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  // (in their order along their line: from the model's own to the most)
  let order = ["默认", "低", "中", "高", "最高"].map(fn(l) { t.get(Radio, label=l).rect })
  for i in 1..<order.length() {
    assert_true(order[i].1 == order[0].1 && order[i].0 > order[i - 1].0, msg="\{order}")
  }
  let (px, _, pw, _) = t.get(@ui.Role::Dialog).rect
  assert_true(order[order.length() - 1].0 + order[order.length() - 1].2 <= px + pw, msg="past the panel")
}
