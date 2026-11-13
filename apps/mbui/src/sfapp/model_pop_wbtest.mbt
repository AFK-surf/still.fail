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
test "wide, short names: the model's panel as wide as what it holds, not as wide as it may be" {
  let t = model_pop("newchat-model")
  let (px, _, pw, _) = t.get(@ui.Role::Dialog).rect
  let effort = t.get(Radio, label="高").rect
  // (what it holds narrow, its foot the widest of it: far narrower than the most it may be)
  assert_true(pw < 2.0 * @sfpages.triple_models_least, msg="\{Repr(t.get(@ui.Role::Dialog).rect)}")
  assert_true(effort.0 + effort.2 <= px + pw - @sf.panel_pad, msg="\{Repr(t.get(@ui.Role::Dialog).rect)} \{Repr(effort)}")
  let model = t.get(Button, label="Opus 5.5").rect
  assert_true(model.0 + model.2 <= px + pw)
}

///|
test "choosing a frequent model fades the model words with the panel" {
  let t = model_pop("newchat-crowded-model")
  let (x, y, w, h) = t.get(@ui.Role::Dialog).rect
  let heading = t.words().filter(fn(item) { item.0 == "常用搭配" }).last().unwrap()
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
  assert_true(!before.is_empty(), msg="those used most are titled")
  let ink = before.last().unwrap().2
  t.click(Button, label="GPT-6 Astra · 中")
  t.run_for(@kit.pop_out_ms / 2.0)
  let faded = t.drawn_rects().filter(fn(r) {
    r.4 >> 8 == original.4 >> 8 &&
    (r.0 - original.0).abs() < 10.0 && (r.1 - original.1).abs() < 10.0 &&
    r.2 > original.2 * 0.96 && r.3 > original.3 * 0.96
  })
  let words = t.drawn_glyphs().filter(fn(g) { in_heading(g) && g.2 >> 8 == ink >> 8 })
  assert_eq(faded.length(), 1, msg="the model panel remains during its fade")
  assert_true(!words.is_empty(), msg="their title remains during its fade")
  let surface_alpha = faded[0].4 & 0xFFL
  let word_alpha = words.last().unwrap().2 & 0xFFL
  assert_true(surface_alpha > 0L && surface_alpha < 255L, msg="the surface is fading: \{surface_alpha}, its words \{word_alpha}")
  let difference = word_alpha * (original.4 & 0xFFL) - surface_alpha * (ink & 0xFFL)
  assert_true(difference >= -255L && difference <= 255L, msg="the model words and surface fade together")
}

///|
test "a frequent model with a different runtime is applied as its panel leaves without the contents jumping" {
  let t = model_pop("newchat-crowded-model")
  let before = t.find("常用搭配").unwrap()
  let words = fn(name : String) { t.words().filter(fn(w) { w.0 == name }).last().unwrap() }
  let heading = words("常用搭配")
  let row = words("SWE-2")
  let other = words("DeepSeek V4.1 Flash")
  assert_true(t.find("DeepSeek Harness") is Some(_))
  t.click(Button, label="GPT-6 Astra · 中")
  assert_eq(new_fix.model, "gpt-6-astra")
  assert_eq(t.find("常用搭配"), Some(before), msg="the model rows stay where they were as the panel starts to close")
  assert_true(t.find("DeepSeek Harness") is Some(_), msg="the leaving panel keeps the runtime that was shown")
  t.run_for(@kit.pop_out_ms / 2.0)
  // The rows' layout stays fixed while the panel fades and shrinks.
  let heading_out = words("常用搭配")
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
test "a new chat's model panel opens where it stays: what the page has shown until its own is read, not first in its bones elsewhere" {
  // (its own pick read a while after it opens, as a core across a thread answers it; the page's already there)
  let held = Ref(true)
  let base = fixture_app("newchat-crowded-model")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      @settings.fixture_followed()
      if name == "pick" && held.val {
        { value: None, error: None, version: -1 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  @sffixture.fix_later(120.0, fn() { held.val = false })
  let rects : Array[(Double, Double, Double, Double)] = []
  let till = t.time() + 400.0
  while t.time() < till {
    t.frame()
    match t.query(@ui.Role::Dialog) {
      Some(d) => if rects.last() != Some(d.rect) { rects.push(d.rect) }
      None => ()
    }
  }
  assert_true(!held.val, msg="its own read")
  // (each frame as it ends up, only grown into it from the side it opens from as it comes in: the same corner, the
  // same shape)
  let (fx, fy, fw, fh) = rects.last().unwrap()
  assert_true(
    rects.iter().all(fn(r) {
      (r.0 - fx).abs() < 1.0 && (r.1 + r.3 - (fy + fh)).abs() < 1.0 && (r.2 / r.3 - fw / fh).abs() < 0.02 * fw / fh
    }),
    msg="\{Repr(rects)}",
  )
}

///|
/// A model pop of the fixture's `mode` whose calls are kept in `calls` (and answered by the fixture), with `liked`
/// starred before it opens.
fn model_pop_calls(mode : String, calls : Array[(String, Json)], liked? : Array[String] = []) -> @ui.Tester {
  let base = fixture_app(mode)
  new_fix.liked.push_iter(liked.iter())
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push((name, params))
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  t
}

///|
/// What the screen of `mode` (a new chat's page, its model's panel not open) is faulted for by `Tester::audit`: what
/// the panel's screen is held to past it.
fn page_faults(mode : String) -> Array[String] {
  let src = fixture_app(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  t.audit()
}

///|
/// Whether the rect `r` is wholly in view in the panel: inside the part seen of every box of the panel's laid out round
/// it (a scroller's, the panel's own), so nothing over its foot or past a scroller's edge hides any of it.
fn wholly_in_view(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Bool raise {
  let (x, y, w, h) = r
  let (dx, _, dw, _) = t.get(@ui.Role::Dialog).rect
  t
  .boxes()
  .iter()
  .all(fn(b) {
    let holds = b.x >= dx - 0.5 && b.x + b.w <= dx + dw + 0.5 &&
      b.x <= x + 0.5 && x + w <= b.x + b.w + 0.5 && b.y <= y + 0.5 && y + h <= b.y + b.h + 0.5
    let (cx, cy, cw, ch) = b.cut
    !holds || (cx <= x + 0.5 && x + w <= cx + cw + 0.5 && cy <= y + 0.5 && y + h <= cy + ch + 0.5)
  })
}

///|
test "wide, crowded, the panel gone up from its control: the configuration used most wholly in view at its foot as it opens; pressed, all of it saved" {
  // (the panel is first built as one going down and found to stand above its control once laid out: the row nearest
  // the hand was brought into view for the other order and left a row past the scroller's foot, under the panel's)
  let calls = []
  let t = model_pop_calls("newchat-crowded-model", calls)
  t.run_for(@ui.move_most_ms)
  let first = t.get(Button, label="GPT-6 Astra · 中").rect
  let foot = t.get(Button, label="DeepSeek Harness").rect
  assert_true(wholly_in_view(t, first), msg="\{Repr(first)}")
  assert_true(first.1 + first.3 <= foot.1, msg="\{Repr(first)} over the foot's \{Repr(foot)}")
  t.click(Button, label="GPT-6 Astra · 中")
  t.run_for(@kit.presence_in_ms)
  let saves = calls.filter(fn(c) { c.0 == "pick.save" })
  assert_eq(saves.length(), 1, msg="\{Repr(saves)}")
  let p = Some(saves[0].1)
  assert_eq((text(p, "model"), text(p, "runtime"), text(p, "effort")), ("gpt-6-astra", "codex", "medium"))
  assert_eq((field(p, "fast"), field(p, "context")), (Some(Json::null()), Some(Json::null())))
}

///|
/// Whether a row's rect `r` holds a model's star (喜欢 …) beside it.
fn starred_beside(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Bool {
  t.all(Button, has="喜欢").iter().any(fn(s) { s.rect.1 >= r.1 - 1.0 && s.rect.1 + s.rect.3 <= r.1 + r.3 + 1.0 })
}

///|
/// The words `name` drawn in the rect `r`.
fn words_in(t : @ui.Tester, r : (Double, Double, Double, Double), name : String) -> @ui.Laid? {
  t.boxes().rev().iter().find_first(fn(b) { b.kind == "text" && b.text == name && b.x >= r.0 && b.x < r.0 + r.2 && b.y >= r.1 && b.y < r.1 + r.3 })
}

///|
test "wide, few models: the configurations used most under 常用搭配, one model run two ways twice, a starred one's there and among the starred, none starred itself; the models over them, each its star" {
  // (what is used most is a configuration, apart from what is starred: the user, 2026-11-10, 「收藏跟常用不一样」
  // 「常用包括了思考深度和速度还有上下文长度」「是一种配置」)
  let held = page_faults("newchat")
  let calls = []
  let t = model_pop_calls("newchat-model", calls, liked=["claude-sonnet-5"])
  let head = t.find("常用搭配").unwrap()
  let combos = ["Opus 5.5 · 高", "GPT-6 · 中", "Opus 5.5 · 高 · 300K", "Sonnet 5 · 低"].map(fn(l) raise { (l, t.get(Button, label=l).rect) })
  let models = ["Opus 5.5", "GPT-6", "Sonnet 5"].map(fn(l) raise { (l, t.get(Button, label=l).rect) })
  let effort = t.get(Radio, label="高").rect
  // (three models: no way to all of them a step further)
  assert_true(t.query(Button, label="全部模型") is None)
  for c in combos {
    // under their name, nearest what opened the panel (its foot: it opens up from the composer); no star
    assert_true(c.1.1 > head.1, msg="\{Repr(c)} under 常用搭配 at \{Repr(head)}")
    assert_true(!starred_beside(t, c.1), msg="\{c.0} has a star")
  }
  // (the most used nearest what opened it)
  assert_true(combos[0].1.1 > combos[1].1.1 && combos[1].1.1 > combos[2].1.1, msg="\{Repr(combos)}")
  for m in models {
    assert_true(m.1.1 < head.1, msg="\{Repr(m)} over 常用搭配 at \{Repr(head)}")
    assert_true(starred_beside(t, m.1), msg="\{m.0} has no star")
    assert_true(effort.0 >= m.1.0 + m.1.2, msg="\{Repr(m)} \{Repr(effort)}")
  }
  // the starred one both among the starred and under 常用搭配, its star lit
  assert_true(t.query(Button, label="喜欢 Sonnet 5") is Some(_))
  // the one it runs on exactly drawn picked, the same model run another way not
  let (on, off) = (combos[0].1, combos[2].1)
  let weight = fn(r) { words_in(t, r, "Opus 5.5").map(fn(b) { b.weight }).unwrap_or(0) }
  assert_true(weight(on) > weight(off), msg="\{weight(on)} \{weight(off)}")
  // how it runs in its capsule after its name
  assert_true(words_in(t, off, "高 · 300K") is Some(_), msg="Opus 5.5's 高 · 300K")
  // pressed: all of it made what it runs on in one save, the panel closed
  t.click(Button, label="Opus 5.5 · 高 · 300K")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.query(@ui.Role::Dialog) is None, msg="its panel closed")
  let saves = calls.filter(fn(c) { c.0 == "pick.save" })
  assert_eq(saves.length(), 1, msg="\{Repr(saves)}")
  let p = Some(saves[0].1)
  assert_eq((text(p, "model"), text(p, "runtime"), text(p, "effort")), ("claude-opus-5-5", "claude", "high"))
  assert_eq(field(p, "fast"), Some(Json::null()))
  assert_eq(field(p, "context"), Some(Json::number(300000.0)))
  assert_eq((new_fix.model, new_fix.runtime, new_fix.effort, new_fix.context), ("claude-opus-5-5", "claude", "high", "300000"))
  assert_eq(t.audit().filter(fn(f) { !held.contains(f) }), [])
}

///|
test "wide, few models: each configuration used most has what takes it out where a star would be; pressed, that one is taken out and leaves the panel at once, the panel open, the rest there; all taken out, 常用搭配 gone with them" {
  // (the user, 2026-11-10: 「常用模型应该是一种特定配置，并且可以删掉，跟模型没有关系」; 2026-11-13: 「删掉常用模型，只有 x
  // 会消失，然后关掉重新打开才能刷新」)
  let held = page_faults("newchat")
  let calls = []
  let t = model_pop_calls("newchat-model", calls, liked=["claude-sonnet-5"])
  let combos = ["Opus 5.5 · 高", "GPT-6 · 中", "Opus 5.5 · 高 · 300K", "Sonnet 5 · 低"]
  let rects = combos.map(fn(l) raise { t.get(Button, label=l).rect })
  for i, l in combos {
    let forget = t.get(Button, label="从常用搭配移除 " + l).rect
    assert_true(!starred_beside(t, rects[i]), msg="\{l} has a star")
    assert_true(
      forget.1 >= rects[i].1 - 1.0 && forget.1 + forget.3 <= rects[i].1 + rects[i].3 + 1.0 && forget.0 >= rects[i].0 + rects[i].2,
      msg="\{l}: \{Repr(forget)} beside \{Repr(rects[i])}",
    )
  }
  assert_eq(t.audit().filter(fn(f) { !held.contains(f) }), [])
  t.click(Button, label="从常用搭配移除 GPT-6 · 中")
  t.run_for(@ui.move_most_ms)
  let forgets = calls.filter(fn(c) { c.0 == "pick.forget" })
  assert_eq(forgets.length(), 1, msg="\{Repr(forgets)}")
  let p = Some(forgets[0].1)
  assert_eq((text(p, "model"), text(p, "runtime"), text(p, "effort")), ("gpt-6", "codex", "medium"))
  assert_eq((field(p, "fast"), field(p, "context")), (Some(Json::null()), Some(Json::null())))
  assert_true(t.query(@ui.Role::Dialog) is Some(_), msg="the panel closed")
  // (taken out: gone from the panel, its words too, the rest there)
  assert_true(t.query(Button, label="从常用搭配移除 GPT-6 · 中") is None && t.query(Button, label="GPT-6 · 中") is None)
  assert_true(words_in(t, rects[1], "中") is None, msg="its words still where it stood")
  for i, l in combos {
    if i != 1 {
      assert_true(t.query(Button, label=l) is Some(_), msg="\{l} gone")
    }
  }
  assert_true(t.query(Button, label="喜欢 Sonnet 5") is Some(_))
  assert_eq(t.audit().filter(fn(f) { !held.contains(f) }), [])
  // the rest taken out: no configuration, nor their name, the panel still open; the starred and the rest there
  for l in ["Opus 5.5 · 高", "Opus 5.5 · 高 · 300K", "Sonnet 5 · 低"] {
    t.click(Button, label="从常用搭配移除 " + l)
    t.run_for(@ui.move_most_ms)
  }
  assert_true(t.query(@ui.Role::Dialog) is Some(_), msg="the panel closed")
  assert_true(t.find("常用搭配") is None, msg="常用搭配 with none under it")
  for l in combos {
    assert_true(t.query(Button, label=l) is None, msg="\{l} still there")
  }
  assert_true(t.query(Button, label="Sonnet 5") is Some(_) && t.query(Button, label="喜欢 Sonnet 5") is Some(_))
}

///|
test "wide, few models: the configuration it runs on pressed sends nothing; another, its model, runtime and how hard it thinks" {
  let held = page_faults("newchat")
  let calls = []
  let t = model_pop_calls("newchat-model", calls)
  t.click(Button, label="Opus 5.5 · 高")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.query(@ui.Role::Dialog) is None, msg="its panel closed")
  assert_eq(calls.filter(fn(c) { c.0 == "pick.save" }).length(), 0, msg="\{Repr(calls)}")
  let t = model_pop_calls("newchat-model", calls)
  t.click(Button, label="GPT-6 · 中")
  t.run_for(@kit.presence_in_ms)
  assert_eq((new_fix.model, new_fix.runtime, new_fix.effort, new_fix.context), ("gpt-6", "codex", "medium", ""))
  let p = Some(calls.filter(fn(c) { c.0 == "pick.save" })[0].1)
  assert_eq(field(p, "context"), Some(Json::null()))
  assert_eq(t.audit().filter(fn(f) { !held.contains(f) }), [])
}

///|
test "wide, many models: those used most, the way to all of them; there, a maker's models; every row's star beside it starred or not at a press, the panel open, the row where it was" {
  let t = model_pop("newchat-providers-model")
  assert_true(t.query(Button, label="Sonnet 5") is None, msg="neither used most nor starred: a step further")
  t.click(Button, label="全部模型")
  t.run_for(@kit.presence_in_ms)
  // the makers beside a maker's models
  assert_true(t.query(Button, label="Anthropic") is Some(_) && t.query(Button, label="OpenAI") is Some(_))
  t.click(Button, label="Anthropic")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.query(Button, label="Opus 5.5") is Some(_) && t.query(Button, label="Gemini 3 Pro") is None, msg="Anthropic's alone")
  // its star pressed: starred (the same star on every row of the panel, in place of a box before a maker's models;
  // the user, 2026-11-10, of a ticked box read as the model picked)
  t.click(Button, label="喜欢 Sonnet 5")
  t.run_for(@kit.presence_in_ms)
  assert_eq(new_fix.liked, ["claude-sonnet-5"])
  assert_true(t.query(@ui.Role::Dialog) is Some(_), msg="the panel stays open")
  // back: Sonnet among the starred, over the configurations used most (none of them starred: a configuration is not)
  t.click(Button, label="全部模型")
  t.run_for(@kit.presence_in_ms)
  let (sonnet, used) = (t.get(Button, label="Sonnet 5").rect.1, t.find("常用搭配").unwrap().1)
  assert_true(sonnet < used, msg="\{sonnet} \{used}")
  // its star pressed there: starred no more, its row where it was while the panel is open
  t.click(Button, label="喜欢 Sonnet 5")
  t.run_for(@kit.presence_in_ms)
  assert_eq(new_fix.liked, [])
  assert_eq(t.get(Button, label="Sonnet 5").rect.1, sonnet, msg="its row gone from under the hand")
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
test "wide, many models and Codex's efforts and speeds: the models, how hard it thinks a column beside them, the runtime and how fast at the foot" {
  let t = model_pop("newchat-tall-model")
  let (px, py, pw, ph) = t.get(@ui.Role::Dialog).rect
  let all = t.get(Button, label="SWE-2").rect
  // how hard it thinks, its levels one under another at the panel's right, beside the models (2026-11-02 用户「思考深度
  // 放在整个面板的右边」「模型跟思考深度的并排的」)
  let levels = ["最低", "低", "中", "高", "很高", "最高", "Ultra"].map(fn(l) raise { t.get(Radio, label=l).rect })
  for i, r in levels {
    assert_true(r.0 == levels[0].0 && r.0 >= all.0 + all.2, msg="\{Repr(levels)}, beside \{Repr(all)}")
    assert_true(i == 0 || r.1 > levels[i - 1].1, msg="\{Repr(levels)}")
    assert_true(r.0 + r.2 <= px + pw && r.1 + r.3 <= py + ph, msg="\{Repr(r)} past the panel")
  }
  // the runtime and how fast at the foot, by who runs it, how fast saying how fast it runs (its account's standard: no
  // 跟随订阅), pressed the two ways in a pick (「速度放在面板下面，跟账号差不多的位置」「运行时不应该放那个位置吧」)
  let runtime = t.get(Button, label="DeepSeek Harness").rect
  let speed = t.get(Button, label="标准").rect
  assert_true(runtime.1 == speed.1, msg="\{Repr(runtime)} \{Repr(speed)}")
  assert_true(speed.1 >= levels[levels.length() - 1].1 + levels[levels.length() - 1].3, msg="\{Repr(speed)}")
  assert_true(t.words().iter().all(fn(w) { w.0 != "跟随订阅" }), msg="跟随订阅 said")
  t.click(Button, label="标准")
  t.run_for(squeeze_opening)
  assert_true(t.words().iter().any(fn(w) { w.0 == "Fast" }), msg="no pick of how fast")
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
    assert_true(now.0 == opened.0 && now.2 == opened.2, msg="\{label} picked: \{Repr(now)}, opened \{Repr(opened)}")
  }
}

///|
test "wide: how much context at the foot after who runs it, as how fast is; its steps in a pick, one picked made what it runs on at once" {
  let t = model_pop("newchat-model")
  let (px, py, pw, ph) = t.get(@ui.Role::Dialog).rect
  let high = t.get(Radio, label="高").rect
  // (at the foot, with who runs it: 2026-11-03 用户「直接放最下面跟速度一样吧」)
  let context = t.get(Button, label="完整 · 1M").rect
  assert_true(context.1 > high.1 + high.3 && context.1 + context.3 <= py + ph && context.0 + context.2 <= px + pw, msg="\{Repr(context)}, the panel \{Repr((px, py, pw, ph))}")
  assert_true(t.words().iter().any(fn(w) { w.0 == "上下文" }), msg="no name before it")
  t.click(Button, label="完整 · 1M")
  t.run_for(@ui.move_most_ms)
  let steps = t.all(MenuItemRadio).map(fn(s) { (s.label, s.check) })
  assert_eq(steps, [("完整 · 1M", Some(On)), ("500K", Some(Off)), ("300K", Some(Off)), ("200K", Some(Off))])
  t.click(MenuItemRadio, label="300K")
  t.run_for(squeeze_opening)
  assert_eq(new_fix.context, "300000")
  assert_true(t.query(Button, label="300K") is Some(_), msg="the foot says the step picked")
}

