// The model's panel beside its control (sfpages model_triple.mbt) in a desktop's window: as wide as its columns'
// words, no wider (2026-10-26 用户「没啥内容也这么宽感觉会很奇怪」), and as wide whichever model is picked in it.

///|
/// The fixture's `mode` in a desktop's window, its model's panel open beside its control.
fn model_pop(mode : String) -> @ui.Tester {
  let src = fixture_app(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  t
}

///|
/// The words `name` as drawn last in the panel (over what the page has under it there): how wide they are, the room
/// they have, their weight.
fn pop_words(t : @ui.Tester, name : String) -> @ui.Laid? raise {
  let (px, py, pw, ph) = t.get(@ui.Dialog).rect
  t
  .boxes()
  .rev()
  .iter()
  .find_first(fn(b) { b.kind == "text" && b.text == name && b.x >= px && b.x < px + pw && b.y >= py && b.y < py + ph })
}

///|
test "wide, short names: the model's panel as wide as what it holds, not as wide as it may be" {
  let t = model_pop("newchat-model")
  let (px, _, pw, _) = t.get(@ui.Dialog).rect
  let effort = t.get(Radio, label="高").rect
  // (what it holds narrow, its foot the widest of it: far narrower than the most it may be)
  assert_true(pw < 2.0 * @sfpages.triple_models_least, msg="\{t.get(@ui.Dialog).rect}")
  assert_true(effort.0 + effort.2 <= px + pw - @sf.panel_pad, msg="\{t.get(@ui.Dialog).rect} \{effort}")
  let model = t.get(Button, label="Opus 5.5").rect
  assert_true(model.0 + model.2 <= px + pw)
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
  let (px, py, pw, ph) = t.get(@ui.Dialog).rect
  let last = t.get(Button, label="GPT-6.1 Terra").rect
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
test "wide: another model picked, its runtimes fewer, the panel as wide as it opened; every name whole on its line" {
  let t = model_pop("newchat-crowded-model")
  let opened = t.get(@ui.Dialog).rect
  for name in ["Opus 5.5", "Grok 4.7 Build Fast", "DeepSeek V4.1 Flash"] {
    t.click(Button, label=name)
    t.run_for(squeeze_opening)
    // (picked, in the picked weight)
    match pop_words(t, name) {
      Some(b) => {
        assert_eq(b.weight, 500, msg="\{name} not picked")
        assert_true(b.words_w <= b.w + 0.5 && b.h < 2.0 * b.font_size, msg="\{name} not whole on one line")
      }
      None => fail("\{name} not drawn")
    }
    // (as wide, its sides where they were; as tall as what it holds now)
    let now = t.get(@ui.Dialog).rect
    assert_true(now.0 == opened.0 && now.2 == opened.2, msg="\{name} picked: \{now}, opened \{opened}")
  }
}
