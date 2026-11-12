// A panel of the presenters' as wide as what it holds (@sf.panel's `fits`) on 中屏 and 大屏: the old contract, measured
// on main first (a4c845604), what it does held whatever draws it.

///|
/// Where what a fits panel shows is: its dialog, its title, its words, its foot's button, what is at its head's end.
fn fits_said(t : @ui.Tester, words : String) -> String {
  let r = fn(role : @ui.Role, label : String) { t.query(role, label~).map(fn(s) { tenth4(s.rect) }) }
  let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  "dialog \{@ui.some_text(r(Dialog, "面板").map(@ui.rect_text))} title \{@ui.list_text(w("面板").map(@ui.rect_text))} words \{@ui.list_text(w(words).map(@ui.rect_text))} button \{@ui.some_text(r(Button, "好的").map(@ui.rect_text))} end \{@ui.some_text(r(Button, "尾").map(@ui.rect_text))}"
}

///|
test "panel fits, 大屏 keyboard and mouse: as wide as its words as they change, never narrower; its foot, a narrower most; a column of its own, the window short of it: as main has it, drawn by the window's tree" {
  let out = []
  let drawn = []
  let long = "一行很长很长的话，比面板最宽的时候还要宽很多很多，好看它怎么折行和怎么定宽度"
  // (its words changing while it is open: short, long, middling, short again)
  for kind in ["plain", "foot", "narrow"] {
    let t = menu_tester(1280.0, 800.0, 0)
    let words = @signals.signal("短短的")
    let w = if kind == "narrow" { 200.0 } else { 400.0 }
    match kind {
      "foot" =>
        @sf.panel(
          "面板",
          fn(c, _) { @sf.panel_text(c, fn() { c.text(words.get(), style=@sf.paragraph) |> ignore }) },
          from=At(600.0, 100.0, 0.0, 0.0),
          fits=true,
          w~,
          foot=fn(c, close) {
            @sf.button(c, "好的", key="ok34", tone=Primary, on_press=fn() {
              close()
            }) |> ignore
          },
        )
      _ => @sf.panel("面板", fits_words_body(words), from=At(600.0, 100.0, 0.0, 0.0), fits=true, w~)
    }
    t.run_for(@ui.move_most_ms)
    for s in ["短短的", long, "中等长度的一句话", "短短的"] {
      words.set(s)
      t.run_for(@ui.move_most_ms)
      out.push("\{kind} \{s.length()}: \{fits_said(t, s)}")
      drawn.push(tree_said(Dialog, "面板") is Some(_))
    }
  }
  // (a column of its own in it, the window short of it)
  let held : Array[Bool] = []
  let t = menu_tester(1280.0, 500.0, 0)
  @sf.panel("面板", panel_column_body(@signals.signal(40), held), from=At(600.0, 100.0, 0.0, 0.0), fits=true, w=400.0)
  t.run_for(@ui.move_most_ms)
  let d = t.get(Dialog, label="面板").rect
  let row0 = fn() { t.words().filter(fn(x) { x.0 == "第0行" }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  let before = "column: dialog \{@ui.rect_text(tenth4(d))} row0 \{@ui.list_text(row0().map(@ui.rect_text))} held \{@ui.some_text(held.last())}"
  t.wheel(d.0 + d.2 / 2.0, d.1 + 120.0, 120.0)
  t.run_for(@ui.move_most_ms)
  out.push("\{before} | wheel: \{@ui.list_text(row0().map(@ui.rect_text))}")
  drawn.push(tree_said(Dialog, "面板") is Some(_))
  // (as main has it, a4c845604)
  assert_eq(out, fits_main)
  assert_eq(drawn, Array::make(drawn.length(), true))
}

///|
test "panel fits, the model's (model_pop): where it is, its models and how hard it thinks, another effort picked: as main has it, drawn by the window's tree" {
  let out = []
  let drawn = []
  for mode in ["newchat-model", "newchat-tall-model", "newchat-crowded-model"] {
    let t = model_pop(mode)
    let r = fn(role : @ui.Role, label : String) { t.query(role, label~).map(fn(s) { tenth4(s.rect) }) }
    out.push("\{mode}: dialog \{@ui.some_text(t.query(Dialog).map(fn(s) { tenth4(s.rect) }).map(@ui.rect_text))} opus \{@ui.some_text(r(Button, "Opus 5.5").map(@ui.rect_text))} high \{@ui.some_text(r(Radio, "高").map(@ui.rect_text))}")
    // (the row it runs on, the configuration picked exactly, wholly in view as it opens: Opus above it a model scrolled
    // past, not the one picked)
    let runs_on = if mode == "newchat-model" { "Opus 5.5 · 高" } else { "DeepSeek V4.1 Flash · DSH · 高" }
    let on = t.get(Button, label=runs_on)
    assert_true(wholly_in_view(t, on.rect), msg="\{mode}: \{runs_on} at \{Repr(on.rect)} out of view")
    drawn.push(tree_said(Dialog, t.query(Dialog).map(fn(s) { s.label }).unwrap_or("")) is Some(_))
    if mode == "newchat-crowded-model" {
      for label in ["低", "最高"] {
        t.click(Radio, label~)
        t.run_for(squeeze_opening)
        out.push("\{mode} \{label}: dialog \{@ui.some_text(t.query(Dialog).map(fn(s) { tenth4(s.rect) }).map(@ui.rect_text))} high \{@ui.some_text(r(Radio, "高").map(@ui.rect_text))}")
      }
    }
  }
  // (as main has it, a4c845604; since 2026-11-02 the tall and the crowded open on those used most and starred alone, the
  // rest a step further, room between its parts: Opus not among them; since 2026-11-02 how each runs right after its
  // name, how hard it thinks a column beside the models, each titled, the runtime and how fast at the foot under a line;
  // since 2026-11-03 how much context at the foot too: a Claude model's panel as wide as its foot; since 2026-11-10
  // twelve models or fewer all in the one list, those used most titled under the rest, a star beside every row, and
  // room for the widest level after each name: Opus among them in all three, each panel taller and the crowded wider;
  // since the user, 2026-11-10 (「收藏跟常用不一样」「常用包括了思考深度和速度还有上下文长度」「是一种配置」), those used
  // most a configuration a row each under 常用搭配, the starred models apart: each panel taller still, the plain one to
  // its most, the tall and the crowded scrolling, opened at their foot where the configuration they run on is (held
  // above: wholly in view), Opus a model scrolled past over the panel's top; how each runs said with its runtime's short
  // name (「agent runtime 可以用缩写，比如 CC，DSH」): the crowded narrower than with DeepSeek Harness spelt out)
  assert_eq(out, [
    "newchat-model: dialog Some((650, 139, 313, 387)) opus Some((656, 175, 188, 36)) high Some((885, 250, 72, 36))",
    "newchat-tall-model: dialog Some((650, 65, 520, 461)) opus Some((656, -47, 394.5, 36)) high Some((1091.5, 213, 72.5, 36))",
    "newchat-crowded-model: dialog Some((650, 75, 379, 451)) opus Some((656, 27, 254, 36)) high Some((951, 186, 72, 36))",
    "newchat-crowded-model 低: dialog Some((650, 75, 379, 451)) high Some((951, 186, 72, 36))",
    "newchat-crowded-model 最高: dialog Some((650, 75, 379, 451)) high Some((951, 186, 72, 36))",
  ])
  assert_eq(drawn, [true, true, true])
}

///|
/// The fits panels' test as main has it (a4c845604): each kind as its words change, short (3), long (38), middling (8),
/// short again; then the column's.
// kept across runs: a value (no field of it changes)
let fits_main : Array[String] = [
  "plain 3: dialog Some((600, 106, 74, 64)) title [(616, 118, 42, 20)] words [(616, 142, 42, 22)] button None end None",
  "plain 38: dialog Some((600, 106, 400, 86)) title [(616, 118, 368, 20)] words [(616, 142, 368, 44)] button None end None",
  "plain 8: dialog Some((600, 106, 400, 64)) title [(616, 118, 368, 20)] words [(616, 142, 368, 22)] button None end None",
  "plain 3: dialog Some((600, 106, 400, 64)) title [(616, 118, 368, 20)] words [(616, 142, 368, 22)] button None end None",
  "foot 3: dialog Some((600, 106, 74, 108)) title [(616, 118, 42, 20)] words [(616, 142, 42, 22)] button Some((610, 172, 58, 36)) end None",
  "foot 38: dialog Some((600, 106, 400, 130)) title [(616, 118, 368, 20)] words [(616, 142, 368, 44)] button Some((936, 194, 58, 36)) end None",
  "foot 8: dialog Some((600, 106, 400, 108)) title [(616, 118, 368, 20)] words [(616, 142, 368, 22)] button Some((936, 172, 58, 36)) end None",
  "foot 3: dialog Some((600, 106, 400, 108)) title [(616, 118, 368, 20)] words [(616, 142, 368, 22)] button Some((936, 172, 58, 36)) end None",
  "narrow 3: dialog Some((600, 106, 74, 64)) title [(616, 118, 42, 20)] words [(616, 142, 42, 22)] button None end None",
  "narrow 38: dialog Some((600, 106, 200, 130)) title [(616, 118, 168, 20)] words [(616, 142, 168, 88)] button None end None",
  "narrow 8: dialog Some((600, 106, 200, 64)) title [(616, 118, 168, 20)] words [(616, 142, 168, 22)] button None end None",
  "narrow 3: dialog Some((600, 106, 200, 64)) title [(616, 118, 168, 20)] words [(616, 142, 168, 22)] button None end None",
  "column: dialog (600, 90, 74, 402) row0 [(616, 126, 42, 22)] held Some(false) | wheel: [(616, 6, 42, 22)]",
]
