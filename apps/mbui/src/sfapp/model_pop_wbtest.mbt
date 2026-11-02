// The model's panel beside its control (sfpages model_triple.mbt) in a desktop's window: as wide as its columns'
// words, no wider (2026-10-26 用户「没啥内容也这么宽感觉会很奇怪」), and as wide whichever model is picked in it.

///|
/// The fixture's `mode` in a desktop's window, its model's panel open beside its control.
fn model_pop(mode : String) -> @ui.Tester {
  let src = fixture_app(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  t
}

///|
/// The words `name` as drawn last in the panel (over what the page has under it there): how wide they are, the room
/// they have, their weight.
fn pop_words(t : @ui.Tester, name : String) -> @ui.Laid? raise {
  let (px, py, pw, ph) = t.get(@ui.Role::Dialog).rect
  t
  .boxes()
  .rev()
  .iter()
  .find_first(fn(b) { b.kind == "text" && b.text == name && b.x >= px && b.x < px + pw && b.y >= py && b.y < py + ph })
}

///|
test "wide, short names: the model's panel as wide as what it holds, not as wide as it may be" {
  let t = model_pop("newchat-model")
  let (px, _, pw, _) = t.get(@ui.Role::Dialog).rect
  let effort = t.get(Radio, label="高").rect
  // (what it holds narrow, its foot the widest of it: far narrower than the most it may be)
  assert_true(pw < 2.0 * @sfpages.triple_models_least, msg="\{t.get(@ui.Role::Dialog).rect}")
  assert_true(effort.0 + effort.2 <= px + pw - @sf.panel_pad, msg="\{t.get(@ui.Role::Dialog).rect} \{effort}")
  let model = t.get(Button, label="Opus 5.5").rect
  assert_true(model.0 + model.2 <= px + pw)
}

///|
test "choosing a frequent model fades the model words with the panel" {
  let t = model_pop("newchat-crowded-model")
  let (x, y, w, h) = t.get(@ui.Role::Dialog).rect
  let heading = t.words().filter(fn(item) { item.0 == "常用" }).last().unwrap()
  let surfaces = t.drawn_rects().filter(fn(r) {
    (r.0 - x).abs() < 0.1 && (r.1 - y).abs() < 0.1 &&
    (r.2 - w).abs() < 0.1 && (r.3 - h).abs() < 0.1 && (r.4 & 0xFFL) > 0L
  })
  assert_eq(surfaces.length(), 1, msg="the model panel's surface")
  let original = surfaces[0]
  let in_heading = fn(g : (Double, Double, Int64)) {
    g.0 >= heading.1 - 2.0 && g.0 < heading.1 + heading.3 + 2.0 &&
    g.1 >= heading.2 - 2.0 && g.1 < heading.2 + heading.4 + 2.0
  }
  let before = t.drawn_glyphs().filter(in_heading)
  assert_true(!before.is_empty(), msg="the frequent-model heading is drawn")
  let ink = before.last().unwrap().2
  t.click(Button, label="GPT-6 Astra")
  t.run_for(@kit.pop_out_ms / 2.0)
  let faded = t.drawn_rects().filter(fn(r) {
    r.4 >> 8 == original.4 >> 8 &&
    (r.0 - original.0).abs() < 10.0 && (r.1 - original.1).abs() < 10.0 &&
    r.2 > original.2 * 0.96 && r.3 > original.3 * 0.96
  })
  let words = t.drawn_glyphs().filter(fn(g) { in_heading(g) && g.2 >> 8 == ink >> 8 })
  assert_eq(faded.length(), 1, msg="the model panel remains during its fade")
  assert_true(!words.is_empty(), msg="the frequent-model heading remains during its fade")
  let surface_alpha = faded[0].4 & 0xFFL
  let word_alpha = words.last().unwrap().2 & 0xFFL
  assert_true(surface_alpha > 0L && surface_alpha < 255L, msg="the surface is fading")
  let difference = word_alpha * (original.4 & 0xFFL) - surface_alpha * (ink & 0xFFL)
  assert_true(difference >= -255L && difference <= 255L, msg="the model words and surface fade together")
}

///|
test "a frequent model with a different runtime is applied as its panel leaves without the contents jumping" {
  let t = model_pop("newchat-crowded-model")
  let before = t.find("常用").unwrap()
  let words = fn(name : String) { t.words().filter(fn(w) { w.0 == name }).last().unwrap() }
  let heading = words("常用")
  let row = words("SWE-2")
  let other = words("DeepSeek V4.1 Flash")
  assert_true(t.find("DeepSeek Harness") is Some(_))
  t.click(Button, label="GPT-6 Astra")
  assert_eq(new_fix.model, "gpt-6-astra")
  assert_eq(t.find("常用"), Some(before), msg="the model rows stay where they were as the panel starts to close")
  assert_true(t.find("DeepSeek Harness") is Some(_), msg="the leaving panel keeps the runtime that was shown")
  t.run_for(@kit.pop_out_ms / 2.0)
  // The rows' layout stays fixed while the panel fades and shrinks.
  let heading_out = words("常用")
  let row_out = words("SWE-2")
  let other_out = words("DeepSeek V4.1 Flash")
  assert_true(((row_out.2 - heading_out.2) - (row.2 - heading.2)).abs() < 1.0, msg="the model rows keep their layout")
  assert_true(((other_out.2 - heading_out.2) - (other.2 - heading.2)).abs() < 1.0, msg="the other model row keeps its layout")
  assert_true(t.find("DeepSeek Harness") is Some(_), msg="the runtime stays with the leaving panel")
  // Open it again while the first panel is still leaving: the new one has its own, current contents.
  t.tap_text("GPT-6 Astra")
  t.run_for(@kit.pop_ms)
  assert_true(t.query(@ui.Role::Dialog) is Some(_), msg="the panel opens again")
  assert_true(t.query(Button, label="DeepSeek Harness") is None, msg="the reopened panel shows the new model")
}

///|
/// Whether `a`, `b`, `c` lie in that order along the panel, one way or the other.
fn in_line(a : Double, b : Double, c : Double) -> Bool {
  (a < b && b < c) || (a > b && b > c)
}

///|
test "wide: the models used most between the way to all of them and how hard it thinks, the most used nearest it, each saying how it runs; one pressed is made what it runs on and the panel closes" {
  let t = model_pop("newchat-model")
  let (opus, gpt, all) = (
    t.get(Button, label="Opus 5.5").rect,
    t.get(Button, label="GPT-6").rect,
    t.get(Button, label="全部模型").rect,
  )
  let effort = t.get(Radio, label="高").rect
  // (2026-11-01 用户「那它就不应该跑到离按钮很远的最顶上去啊」)
  assert_true(in_line(all.1, gpt.1, opus.1) && in_line(gpt.1, opus.1, effort.1), msg="\{all} \{gpt} \{opus} \{effort}")
  assert_true(t.query(Button, label="Sonnet 5") is None, msg="the rest a step further")
  // how it last ran, at its row's end
  assert_true(
    t.boxes().iter().any(fn(b) { b.kind == "text" && b.text == "中" && b.y >= gpt.1 && b.y + b.h <= gpt.1 + gpt.3 }),
    msg="GPT-6's 中",
  )
  t.click(Button, label="GPT-6")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.query(@ui.Role::Dialog) is None, msg="its panel closed")
  assert_eq((new_fix.model, new_fix.runtime, new_fix.effort), ("gpt-6", "codex", "medium"))
}

///|
test "wide: two levels: those used most, those starred, the way to all of them; there, a maker's models, each starred by the box before it" {
  let t = model_pop("newchat-model")
  assert_true(t.query(Button, label="Sonnet 5") is None, msg="neither used most nor starred: a step further")
  assert_true(t.query(Checkbox, label="喜欢 Opus 5.5") is None, msg="no box among those used most")
  t.click(Button, label="全部模型")
  t.run_for(@kit.presence_in_ms)
  // the makers beside a maker's models: the picked model's, Anthropic's
  assert_true(t.query(Button, label="Anthropic") is Some(_) && t.query(Button, label="OpenAI") is Some(_))
  assert_true(t.query(Button, label="Opus 5.5") is Some(_) && t.query(Button, label="GPT-6") is None, msg="Anthropic's alone")
  // its box ticked: starred
  t.click(Checkbox, label="喜欢 Sonnet 5")
  t.run_for(@kit.presence_in_ms)
  assert_eq(new_fix.liked, ["claude-sonnet-5"])
  assert_true(t.query(@ui.Role::Dialog) is Some(_), msg="the panel stays open")
  // another maker's
  t.click(Button, label="OpenAI")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.query(Button, label="GPT-6") is Some(_) && t.query(Button, label="Sonnet 5") is None)
  // back: Sonnet past those used most, no head of its own
  t.click(Button, label="全部模型")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("喜欢") is None, msg="no head")
  let (opus, gpt, sonnet) = (t.get(Button, label="Opus 5.5").rect.1, t.get(Button, label="GPT-6").rect.1, t.get(Button, label="Sonnet 5").rect.1)
  assert_true(in_line(sonnet, gpt, opus), msg="\{sonnet} \{gpt} \{opus}")
  // its box unticked there: gone from 喜欢
  t.click(Button, label="全部模型")
  t.run_for(@kit.presence_in_ms)
  t.click(Button, label="Anthropic")
  t.run_for(@kit.presence_in_ms)
  t.click(Checkbox, label="喜欢 Sonnet 5")
  t.run_for(@kit.presence_in_ms)
  assert_eq(new_fix.liked, [])
}

///|
test "wide, models of many makers: each a row of its own in the list of them, none cut short" {
  let t = model_pop("newchat-providers-model")
  t.click(Button, label="全部模型")
  t.run_for(@kit.presence_in_ms)
  for k in ["Anthropic", "OpenAI", "DeepSeek", "Google"] {
    assert_true(t.query(Button, label=k) is Some(_), msg=k)
  }
  t.click(Button, label="Google")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.query(Button, label="Gemini 3 Pro") is Some(_) && t.query(Button, label="Opus 5.5") is None)
  assert_eq(t.squeeze_faults(), [])
}

///|
/// The thumbs drawn in how hard it thinks (lifted out of its track: the boxes there with a line round them) as they
/// show, their left edges.
fn meter_thumbs(t : @ui.Tester) -> Array[Double] raise {
  let (x0, y0, _, h0) = t.get(Radio, label="默认").rect
  let (x1, _, w1, _) = t.get(Radio, label="高").rect
  t
  .boxes()
  .filter(fn(b) {
    b.kind != "text" &&
    b.border_w > 0.0 &&
    b.opacity > 0.01 &&
    b.x >= x0 - 1.0 &&
    b.x + b.w <= x1 + w1 + 1.0 &&
    b.y >= y0 - 1.0 &&
    b.y + b.h <= y0 + h0 + 1.0
  })
  .map(fn(b) { b.x })
}

///|
test "wide: another effort picked, its thumb slides there, one thumb all the way (2026-10-31 用户「思考深度的滑块动效有点拉鸡」)" {
  let t = model_pop("newchat-model")
  let from = t.get(Radio, label="高").rect.0
  let to = t.get(Radio, label="默认").rect.0
  assert_eq(meter_thumbs(t).length(), 1)
  t.click(Radio, label="默认")
  // (half its way: one thumb, between where it was and where it goes, not one fading out over another fading in)
  t.run_for(@ui.move_ms(from - to) / 2.0)
  let mid = meter_thumbs(t)
  assert_eq(mid.length(), 1, msg="\{mid}")
  assert_true(mid[0] > to + 1.0 && mid[0] < from - 1.0, msg="\{mid} \{to} \{from}")
  t.run_for(@ui.move_ms(from - to))
  let end = meter_thumbs(t)
  assert_eq(end.length(), 1, msg="\{end}")
  assert_true((end[0] - to).abs() < 1.0, msg="\{end} \{to}")
}

///|
test "wide, many models and Codex's efforts and speeds: the models, how hard it thinks on a line of its own, the runtime and how fast a row each, in the panel" {
  let t = model_pop("newchat-tall-model")
  let (px, py, pw, ph) = t.get(@ui.Role::Dialog).rect
  let last = t.get(Button, label="全部模型").rect
  // how hard it thinks, its levels on one line under the models
  let levels = ["默认", "最低", "低", "中", "高", "很高", "最高", "Ultra"].map(fn(l) { t.get(Radio, label=l).rect })
  for r in levels {
    assert_true(r.1 == levels[0].1 && r.1 >= last.1 + last.3, msg="\{levels}, under \{last}")
    assert_true(r.0 >= px && r.0 + r.2 <= px + pw, msg="\{r} past the panel")
  }
  // the runtime, then how fast, each a row of the panel's under them, in the panel
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  let speed = t.get(Button, label="跟随订阅").rect
  assert_true(runtime.1 >= levels[0].1 + levels[0].3 && speed.1 >= runtime.1 + runtime.3, msg="\{runtime} \{speed}")
  assert_true(speed.0 >= px && speed.0 + speed.2 <= px + pw && speed.1 + speed.3 <= py + ph, msg="\{speed}")
}

///|
test "wide: how hard it thinks picked in the panel is made what it runs on at once, the panel open as wide as it opened" {
  let t = model_pop("newchat-crowded-model")
  let opened = t.get(@ui.Role::Dialog).rect
  for (label, effort) in [("低", "low"), ("最高", "max")] {
    t.click(Radio, label~)
    t.run_for(squeeze_opening)
    assert_eq(new_fix.effort, effort)
    let now = t.get(@ui.Role::Dialog).rect
    assert_true(now.0 == opened.0 && now.2 == opened.2, msg="\{label} picked: \{now}, opened \{opened}")
  }
}
