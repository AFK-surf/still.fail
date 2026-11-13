// A new chat on a narrow phone, what it runs on as crowded as a person's phone showed it (newchat_fixture.mbt
// newchat-crowded, 2026-10-26): the station's and the model's controls over the composer, the model's panel and
// the configurations used most in it; each of their words whole, on one line, in the window.

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
/// The glass controls over the composer, in their order: the preset's, the station's, the model's.
fn crowded_controls(t : @ui.Tester) -> Array[@ui.Laid] {
  t.boxes().filter(fn(b) { b.glass && b.kind == "row" && (b.h - 30.0).abs() < 0.5 })
}

///|
test "narrow: the preset's, the station's and the model's controls side by side, what each says whole or left out, the model's name whole" {
  let t = crowded("newchat-crowded", w=crowded_narrowest)
  // the three glass controls over the composer, side by side in the window
  let glass = crowded_controls(t)
  assert_eq(glass.length(), 3, msg="\{Repr(t.boxes().filter(fn(b) { b.glass }).map(fn(b) { (b.kind, b.x, b.y, b.w, b.h) }))}")
  let (preset, station, model) = (glass[0], glass[1], glass[2])
  assert_true(preset.x + preset.w <= station.x)
  assert_true(station.x + station.w <= model.x)
  assert_true(model.x + model.w <= crowded_narrowest)
  // what the preset's and the station's say: whole, or left out (never 「Stu…」, 「预…」)
  let preset_words = runs_in(t, (preset.x, preset.y, preset.w, preset.h))
  assert_true(preset_words.iter().all(fn(r) { r.text == "预设" }), msg="\{Repr(preset_words.map(fn(r) { r.text }))}")
  let station_words = runs_in(t, (station.x, station.y, station.w, station.h))
  assert_true(station_words.iter().all(fn(r) { r.text == "Willow" }), msg="\{Repr(station_words.map(fn(r) { r.text }))}")
  // the model's: as wide as what it keeps (its padding past the last of it, no more)
  let kept = t
    .boxes()
    .filter(fn(b) { b.parent == model.index && b.opacity > 0.0 && b.w > 0.0 })
    .fold(init=0.0, fn(m, b) { if b.x + b.w > m { b.x + b.w } else { m } })
  assert_true(model.x + model.w - kept <= 12.5, msg="\{model.x + model.w - kept} past what it keeps")
  // what it keeps of itself: the model's name, whole
  let model_words = runs_in(t, (model.x, model.y, model.w, model.h))
  assert_true(model_words.iter().any(fn(r) { r.text == "DeepSeek V4.1 Flash" }), msg="\{Repr(model_words.map(fn(r) { r.text }))} in \{model.w}; \{preset.w}, \{station.w}")
}

///|
test "narrower still: the preset's words and the station's name leave their controls whole after what the model's leaves, the model's name stays, cut short last" {
  let t = crowded("newchat-crowded", w=crowded_cramped)
  let glass = crowded_controls(t)
  assert_eq(glass.length(), 3)
  let (preset, station, model) = (glass[0], glass[1], glass[2])
  assert_true(model.x + model.w <= crowded_cramped)
  // no part of their words: their marks and their chevrons (the page says where it starts)
  let words = runs_in(t, (preset.x, preset.y, station.x + station.w - preset.x, station.h))
  assert_true(words.length() == 0, msg="\{Repr(words.map(fn(r) { r.text }))}")
  // narrower than phones are: the model's name kept, cut short once all else has gone
  let model_words = runs_in(t, (model.x, model.y, model.w, model.h))
  assert_true(model_words.iter().any(fn(r) { r.text.has_prefix("DeepSeek") }), msg="\{Repr(model_words.map(fn(r) { r.text }))}")
  // nothing past what it keeps
  let kept = t
    .boxes()
    .filter(fn(b) { b.parent == model.index && b.opacity > 0.0 && b.w > 0.0 })
    .fold(init=0.0, fn(m, b) { if b.x + b.w > m { b.x + b.w } else { m } })
  assert_true(model.x + model.w - kept <= 12.5)
}

///|
test "narrow: the configurations used most under their title nearest how hard it thinks, one model run two ways twice, the models over them, each with how it runs on its line; few models, no step to all of them" {
  let held = crowded("newchat-crowded").audit()
  let t = crowded("newchat-crowded-model")
  run_to_sheet_rest(t)
  let (sx, _, sw, _) = t.get(@ui.Role::Dialog).rect
  let effort = t.get(Slider, label="思考深度").rect
  // (a sheet risen from the screen's foot: what is used most lowest, the most used of all nearest how hard it thinks;
  // the models over them, 常用搭配 between the two: the user, 2026-11-10, 「常用模型配置需要跟普通的收藏模型从 ui 上区分开」;
  // each a configuration, the same model run two ways two of them: 「常用包括了思考深度和速度还有上下文长度」「是一种配置」)
  let rows = [
    "Opus 5.5", "SWE-2", "Kimi For Coding · 高", "GPT-6 Astra · 高", "DeepSeek V4.1 Flash · DSH · 高", "GPT-6 Astra · 中",
  ].map(fn(l) raise { t.get(Button, label=l) })
  for i in 1..<rows.length() {
    assert_true(rows[i].rect.1 > rows[i - 1].rect.1, msg="\{rows[i - 1].label} \{rows[i].label}")
  }
  assert_true(rows[5].rect.1 < effort.1)
  let head = t.find("常用搭配").unwrap()
  assert_true(head.1 > rows[1].rect.1 && head.1 < rows[2].rect.1, msg="常用搭配 at \{Repr(head)}")
  for row in rows {
    let (x, _, w, _) = row.rect
    assert_true(x >= sx && x + w <= sx + sw + 0.5, msg="\{row.label} \{Repr(row.rect)}")
  }
  // (seven models: all of them in the one list, no way to all of them a step further)
  assert_true(t.query(Button, label="全部模型") is None)
  // how each last ran right after its name, on its line: SWE-2's 高, GPT-6 Astra's 中 (the models' words where they
  // are laid out, scrolled out of sight or not); nothing after the one picked, whose own is what the sheet says under
  // the models
  let words_of = fn(label : String) -> Array[String] raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    t.boxes().filter(fn(b) { b.kind == "text" && b.x >= x && b.x + b.w <= x + w + 0.5 && b.y >= y && b.y + b.h <= y + h + 0.5 }).map(fn(b) { b.text })
  }
  assert_true(words_of("SWE-2").contains("高"), msg="\{Repr(words_of("SWE-2"))}")
  assert_true(words_of("GPT-6 Astra").contains("中"), msg="\{Repr(words_of("GPT-6 Astra"))}")
  let deep = words_of("DeepSeek V4.1 Flash")
  assert_true(deep.contains("DeepSeek V4.1 Flash"), msg="\{Repr(deep)}")
  assert_true(deep.iter().all(fn(w) { w == "DeepSeek V4.1 Flash" || w.has_prefix("DeepSeek H") }), msg="\{Repr(deep)}")
  // a configuration: how it runs in its capsule after its name
  let (rx, ry, rw, rh) = rows[4].rect
  assert_true(
    t.boxes().iter().any(fn(b) { b.kind == "text" && b.text == "DSH · 高" && b.x >= rx && b.x < rx + rw && b.y >= ry && b.y < ry + rh }),
    msg="DeepSeek V4.1 Flash's DSH · 高",
  )
  assert_eq(t.audit().filter(fn(f) { !held.contains(f) }), [])
}

///|
test "narrow, models starred: a starred model's configuration under 常用搭配 and the model among the starred, its star there alone; the one it runs on drawn picked; one pressed, all of it made what it runs on" {
  let held = crowded("newchat-crowded-liked").audit()
  let t = crowded("newchat-crowded-model-liked")
  run_to_sheet_rest(t)
  let head = t.find("常用搭配").unwrap()
  let combo = t.get(Button, label="Kimi For Coding · 高").rect
  let model = t.get(Button, label="Kimi For Coding").rect
  assert_true(combo.1 > head.1 && model.1 < head.1, msg="\{Repr(combo)} \{Repr(model)} 常用搭配 at \{Repr(head)}")
  // (the star a model's: beside the model's row, none beside the configuration's)
  let star = t.get(Button, label="喜欢 Kimi For Coding").rect
  assert_true(star.1 >= model.1 - 1.0 && star.1 + star.3 <= model.1 + model.3 + 1.0, msg="\{Repr(star)} \{Repr(model)}")
  assert_true(
    t.all(Button, has="喜欢").iter().all(fn(s) { s.rect.1 + s.rect.3 <= head.1 }),
    msg="a star under 常用搭配",
  )
  // the one it runs on exactly drawn picked (its name the picked weight), the same model run another way not
  let weight = fn(label : String, name : String) -> Int raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    t.boxes().rev().iter().find_first(fn(b) { b.kind == "text" && b.text == name && b.x >= x && b.x < x + w && b.y >= y && b.y < y + h }).map(fn(b) { b.weight }).unwrap_or(0)
  }
  assert_true(
    weight("DeepSeek V4.1 Flash · DSH · 高", "DeepSeek V4.1 Flash") > weight("GPT-6 Astra · 高", "GPT-6 Astra"),
    msg="the picked one not drawn picked",
  )
  assert_true(weight("GPT-6 Astra · 中", "GPT-6 Astra") == weight("GPT-6 Astra · 高", "GPT-6 Astra"))
  assert_eq(t.audit().filter(fn(f) { !held.contains(f) }), [])
  t.click(Button, label="GPT-6 Astra · 高")
  t.run_for(@ui.move_most_ms)
  assert_eq((new_fix.model, new_fix.runtime, new_fix.effort), ("gpt-6-astra", "codex", "high"))
}

///|
test "narrow, crowded: the configuration used most wholly in view nearest how hard it thinks as the sheet opens; pressed, all of it made what it runs on" {
  let t = crowded("newchat-crowded-model")
  t.run_for(@ui.move_most_ms)
  let first = t.get(Button, label="GPT-6 Astra · 中").rect
  let effort = t.get(Slider, label="思考深度").rect
  assert_true(wholly_in_view(t, first), msg="\{Repr(first)}")
  assert_true(first.1 + first.3 <= effort.1, msg="\{Repr(first)} \{Repr(effort)}")
  t.click(Button, label="GPT-6 Astra · 中")
  t.run_for(@ui.move_most_ms)
  assert_eq((new_fix.model, new_fix.runtime, new_fix.effort, new_fix.context), ("gpt-6-astra", "codex", "medium", ""))
}

///|
test "narrow, crowded: a configuration taken out of those used most leaves the sheet at once, the sheet open, the rest there" {
  let t = crowded("newchat-crowded-model-liked")
  t.run_for(@ui.move_most_ms)
  for l in ["GPT-6 Astra · 中", "DeepSeek V4.1 Flash · DSH · 高", "GPT-6 Astra · 高", "Kimi For Coding · 高"] {
    assert_true(t.query(Button, label="从常用搭配移除 " + l) is Some(_), msg="\{l} can not be taken out")
  }
  t.click(Button, label="从常用搭配移除 GPT-6 Astra · 高")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(@ui.Role::Dialog) is Some(_) && t.query(Button, label="从常用搭配移除 GPT-6 Astra · 高") is None)
  assert_true(t.query(Button, label="GPT-6 Astra · 高") is None, msg="still in the sheet")
  assert_true(t.query(Button, label="GPT-6 Astra · 中") is Some(_) && t.query(Button, label="Kimi For Coding") is Some(_))
  assert_eq(new_fix.model, "deepseek-v4-1-flash", msg="a configuration picked")
}

///|
test "narrow: a frequent model is applied without rearranging the sheet as it leaves" {
  let t = crowded("newchat-crowded-model")
  let used = t.find("常用搭配").unwrap()
  let runtime = t.find_last("DeepSeek Harness").unwrap()
  t.click(Button, label="GPT-6 Astra · 中")
  assert_eq(new_fix.model, "gpt-6-astra")
  assert_eq(t.find("常用搭配"), Some(used), msg="the rows stay where they were as the sheet starts to close")
  t.run_for(@kit.pop_out_ms / 2.0)
  let used_out = t.find("常用搭配").unwrap()
  let runtime_out = t.find_last("DeepSeek Harness").unwrap()
  assert_eq(used_out.1 - runtime_out.1, used.1 - runtime.1, msg="the runtime and the rows leave together")
}

///|
test "narrow: no frequent combination left on the new chat's page" {
  let t = crowded("newchat-crowded")
  assert_true(t.query(Button, label="SWE-2 · 高") is None)
}

///|
test "narrow, a short window, models starred and used most: they scroll, how it runs and who runs it under them, none over another" {
  // (2026-11-02 the person's phone: its keyboard up, 账号 over a model; down, over 速度)
  let t = crowded("newchat-providers-model-liked", h=crowded_short)
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Role::Dialog).rect
  assert_true(sheet.3 <= crowded_short * @sf.sheet_most + 1.0, msg="the sheet is \{sheet.3} high")
  let who = t.boxes().iter().find_first(fn(b) { b.kind == "text" && b.text == "账号" && b.y >= sheet.1 })
  guard who is Some(who) else { fail("no 账号 in the sheet") }
  assert_true(who.y + who.h <= sheet.1 + sheet.3, msg="账号 \{who.y} past the sheet \{Repr(sheet)}")
  let effort = t.get(Slider, label="思考深度").rect
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  assert_true(effort.1 + effort.3 <= who.y && runtime.1 >= effort.1 + effort.3, msg="\{Repr(effort)} \{Repr(runtime)} 账号 at \{who.y}")
  // the models in what is left over how it runs, scrolling, the end of them nearest the hand in view: the way to all
  // of them, the last of them
  let all = t.get(Button, label="全部模型").rect
  assert_true(all.1 >= sheet.1 && all.1 + all.3 <= effort.1, msg="全部模型 \{Repr(all)}: the sheet \{Repr(sheet)}, how hard it thinks \{Repr(effort)}")
  let models = t.get(Button, label="GPT-6 Astra · 中").rect
  assert_true(models.1 < effort.1, msg="\{Repr(models)} \{Repr(effort)}")
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
test "narrow: the model's panel has those used most across it, every name whole, how hard it thinks and the runtime under them; all the models a maker at a time, a step further each" {
  // (a window too short for all of them)
  let t = crowded("newchat-providers-model", h=crowded_short)
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Role::Dialog).rect
  for name in ["GPT-6 Astra", "DeepSeek V4.1 Flash", "Kimi For Coding", "DSH · 高"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole in the sheet")
  }
  // how hard it thinks under the models, the runtime at the foot, each saying the one picked, the others a pick away
  // (2026-11-02 用户「手机上只有模型是平铺的」); their words whole, in the sheet
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  let effort = t.get(Slider, label="思考深度").rect
  let model = t.get(Button, label="GPT-6 Astra · 中").rect
  assert_true(effort.1 > model.1 && runtime.1 > effort.1 + effort.3, msg="\{Repr(model)} \{Repr(effort)} \{Repr(runtime)}")
  assert_true(t.query(Radio, label="Claude Code") is None, msg="the runtimes not picked laid out")
  // (how hard it thinks: its stops on one line, the one it is at alone named)
  assert_true(t.query(Radio, label="最高") is None && t.words().iter().all(fn(w) { w.0 != "最高" }), msg="the levels not picked named")
  assert_true(runtime.1 + runtime.3 <= sheet.1 + sheet.3 && runtime.0 + runtime.2 <= sheet.0 + sheet.2)
  for name in ["DeepSeek Harness", "高"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole")
  }
  // all of them, a step in: the makers, more than the sheet has room for, scrolling, how hard it thinks and how it
  // runs under them as under the models; one pressed, its models a step further
  t.click(Button, label="全部模型")
  t.run_for(@ui.move_most_ms)
  let sheet = t.get(@ui.Role::Dialog).rect
  assert_true(sheet.3 <= crowded_short * @sf.sheet_most + 1.0, msg="the sheet is \{sheet.3} high")
  for name in ["Anthropic", "OpenAI", "DeepSeek"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole in the sheet")
  }
  assert_true(t.query(Button, label="GPT-6 Astra · 中") is None, msg="the step before still said")
  assert_true(t.query(Slider, label="思考深度") is Some(_) && t.query(Button, label="DeepSeek Harness") is Some(_))
  t.click(Button, label="Anthropic")
  t.run_for(@ui.move_most_ms)
  let sheet = t.get(@ui.Role::Dialog).rect
  for name in ["Opus 5.5", "Sonnet 5"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole in the sheet")
  }
  assert_true(t.query(Button, label="OpenAI") is None, msg="Anthropic's alone")
  assert_true(t.query(Slider, label="思考深度") is Some(_))
  // back, by the step's key: the makers again
  t.click(Button, label="返回")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="DeepSeek") is Some(_) && t.query(Button, label="Opus 5.5") is None)
  // and by the system's back: its first step, the sheet still open
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="GPT-6 Astra · 中") is Some(_) && t.query(Button, label="DeepSeek") is None)
}

///|
test "narrow, few models: the same panel; one runtime, nothing to choose of it" {
  let t = crowded("newchat-model")
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Role::Dialog).rect
  let model = t.get(Button, label="GPT-6").rect
  assert_true(t.query(Button, label="Claude Code") is None)
  assert_true(t.get(Slider, label="思考深度").rect.1 > model.1)
  for name in ["Opus 5.5", "Sonnet 5", "GPT-6", "高"] {
    assert_true(words_whole(t, name, sheet) is Some(_), msg="\{name} not whole in the sheet")
  }
  // (three models: all of them in the one list)
  assert_true(t.query(Button, label="全部模型") is None)
}

///|
test "narrow: how hard it thinks its stops under the models: one tapped is made what it runs on at once, the sheet open, nothing opened over it" {
  // (2026-11-02 用户「手机上思考深度变回一个 select，点了弹出来」「抽屉」; 2026-11-10: a level a press away in the sheet
  // itself, 「深度改成滑杆」, a model and how hard it thinks picked without a sheet over a sheet)
  let t = crowded("newchat-crowded-model")
  run_to_sheet_rest(t)
  let stops = t.get(Slider, label="思考深度")
  assert_eq(stops.value, "高")
  let (x, y, w, h) = stops.rect
  t.tap(x + w - w / 8.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(new_fix.effort, "max")
  assert_eq(t.get(Slider, label="思考深度").value, "最高")
  assert_eq(t.all(Dialog).length(), 1, msg="a sheet over the sheet")
  assert_true(t.query(Button, label="GPT-6 Astra") is Some(_), msg="the sheet closed")
}

///|
test "wide: the model's panel beside its control has the models, how hard it thinks beside them, the runtime at the foot" {
  let src = fixture_app("newchat-crowded-model")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  // (the models, then the configurations used most at the foot of their column, then how it runs at the panel's foot;
  // seven models: all of them in the one list)
  let model = t.get(Button, label="Opus 5.5").rect
  let used = t.get(Button, label="GPT-6 Astra · 中").rect
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  let effort = t.get(Radio, label="高").rect
  assert_true(model.1 < used.1 && used.1 < runtime.1, msg="\{Repr(model)} \{Repr(used)} \{Repr(runtime)}")
  assert_true(t.query(Button, label="全部模型") is None)
  // (2026-11-02 用户「思考深度放在整个面板的右边」「模型跟思考深度的并排的」)
  assert_true(effort.0 >= used.0 + used.2 && runtime.1 > effort.1, msg="\{Repr(used)} \{Repr(runtime)} \{Repr(effort)}")
  // pressed, the runtimes in a pick
  t.click(Button, label="DeepSeek Harness")
  t.run_for(squeeze_opening)
  // (its words, whatever draws the pick: an old view's or the window's tree's)
  assert_true(t.words().iter().any(fn(w) { w.0 == "Claude Code" }), msg="no pick of the runtimes")
}

///|
test "wide: how hard it thinks one under another, from the least to the most" {
  let src = fixture_app("newchat-crowded-model")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  // (in their order down their column: from the least to the most)
  let order = ["低", "中", "高", "最高"].map(fn(l) raise { t.get(Radio, label=l).rect })
  for i in 1..<order.length() {
    assert_true(order[i].0 == order[0].0 && order[i].1 > order[i - 1].1, msg="\{Repr(order)}")
  }
  let (px, py, pw, ph) = t.get(@ui.Role::Dialog).rect
  let last = order[order.length() - 1]
  assert_true(last.0 + last.2 <= px + pw && last.1 + last.3 <= py + ph, msg="past the panel")
}

///|
test "narrow, a short window, many models starred: the one picked in view as the sheet opens, the lowest of them though it is" {
  // (2026-11-05 用户「模型选择面板打开不会自动滚动到能看见已选择模型的地方」)
  let t = crowded("newchat-providers-model-far", h=crowded_short)
  run_to_sheet_rest(t)
  let sheet = t.get(@ui.Role::Dialog).rect
  let picked = "Sonnet 5"
  let row = t.get(Button, label=picked).rect
  // (the configurations used most stay put under what scrolls: the one picked between the sheet's top and them)
  let used = t.get(Button, label="GPT-6 Astra · 中").rect
  assert_true(row.1 >= sheet.1 && row.1 + row.3 <= used.1, msg="\{picked} \{Repr(row)}: the sheet \{Repr(sheet)}, those used most from \{Repr(used)}")
}

///|
test "closed capsule uses short runtime label and keeps runtime ahead of effort when squeezed" {
  let roomy = crowded("newchat-crowded", w=520.0)
  let roomy_model = crowded_controls(roomy)[2]
  let roomy_texts = runs_in(roomy, (roomy_model.x, roomy_model.y, roomy_model.w, roomy_model.h)).map(fn(r) { r.text })
  assert_true(roomy_texts.contains("DSH") && roomy_texts.contains("高"), msg="\{Repr(roomy_texts)}")
  assert_true(!roomy_texts.contains("DeepSeek Harness"), msg="\{Repr(roomy_texts)}")
  // Narrowed to 420, effort (`高`) drops first while short runtime (`DSH`) stays.
  let squeezed = crowded("newchat-crowded", w=420.0)
  let squeezed_model = crowded_controls(squeezed)[2]
  let squeezed_texts = runs_in(squeezed, (squeezed_model.x, squeezed_model.y, squeezed_model.w, squeezed_model.h)).map(fn(r) { r.text })
  assert_true(squeezed_texts.contains("DSH") && !squeezed_texts.contains("高"), msg="\{Repr(squeezed_texts)}")
}

///|
test "narrower still, a station of no mark of its own: its control keeps a mark where its name gives way, never a bare chevron" {
  // (2026-11-13 the user: 「怎么 station 还会直接挤消失」, a station named Studio of no mark, its control a chevron alone)
  let t = crowded("newchat-crowded-unmarked", w=crowded_cramped)
  let glass = crowded_controls(t)
  assert_eq(glass.length(), 3)
  let station = glass[1]
  let shown = t.boxes().filter(fn(b) { b.parent == station.index && b.opacity > 0.0 && b.w > 0.0 })
  assert_true(shown.length() >= 2, msg="\{Repr(shown.map(fn(b) { (b.kind, b.x, b.w) }))}")
}
