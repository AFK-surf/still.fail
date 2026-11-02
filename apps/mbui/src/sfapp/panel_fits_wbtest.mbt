// A panel of the presenters' as wide as what it holds (@sf.panel's `fits`) on 中屏 and 大屏: the old contract, measured
// on main first (a4c845604), what it does held whatever draws it.

///|
/// Where what a fits panel shows is: its dialog, its title, its words, its foot's button, what is at its head's end.
fn fits_said(t : @ui.Tester, words : String) -> String {
  let r = fn(role : @ui.Role, label : String) { t.query(role, label~).map(fn(s) { tenth4(s.rect) }) }
  let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  "dialog \{r(Dialog, "面板")} title \{w("面板")} words \{w(words)} button \{r(Button, "好的")} end \{r(Button, "尾")}"
}

///|
test "panel fits, 大屏 keyboard and mouse: as wide as its words as they change, never narrower; its foot, its head's end, a narrower most; a column of its own, the window short of it: as main has it, drawn by the window's tree" {
  let out = []
  let drawn = []
  let long = "一行很长很长的话，比面板最宽的时候还要宽很多很多，好看它怎么折行和怎么定宽度"
  // (its words changing while it is open: short, long, middling, short again)
  for kind in ["plain", "foot", "end", "narrow"] {
    let t = menu_tester(1280.0, 800.0, 0)
    let words = @signals.signal("短短的")
    let w = if kind == "narrow" { 200.0 } else { 400.0 }
    match kind {
      "plain" => @sf.panel("面板", fits_words_body(words), from=At(600.0, 100.0, 0.0, 0.0), fits=true, w~)
      "foot" =>
        @sf.panel(
          "面板",
          fn(c, _) { @sf.panel_text(c, fn() { c.text(words.get(), style=@sf.paragraph) |> ignore }) },
          from=At(600.0, 100.0, 0.0, 0.0),
          fits=true,
          w~,
          foot=fn(c, close) {
            if @sf.button(c, "好的", key="ok34", tone=Primary) {
              close()
            }
          },
        )
      _ =>
        @sf.panel(
          "面板",
          fits_words_body(words),
          from=At(600.0, 100.0, 0.0, 0.0),
          fits=true,
          w~,
          head_end=fn(c) {
            if @sf.button(c, "尾", key="end34", tone=Primary) {
              ()
            }
          },
        )
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
  let before = "column: dialog \{tenth4(d)} row0 \{row0()} held \{held.last()}"
  t.wheel(d.0 + d.2 / 2.0, d.1 + 120.0, 120.0)
  t.run_for(@ui.move_most_ms)
  out.push("\{before} | wheel: \{row0()}")
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
    out.push("\{mode}: dialog \{t.query(Dialog).map(fn(s) { tenth4(s.rect) })} opus \{r(Button, "Opus 5.5")} high \{r(Radio, "高")}")
    drawn.push(tree_said(Dialog, t.query(Dialog).map(fn(s) { s.label }).unwrap_or("")) is Some(_))
    if mode == "newchat-crowded-model" {
      for label in ["低", "最高"] {
        t.click(Radio, label~)
        t.run_for(squeeze_opening)
        out.push("\{mode} \{label}: dialog \{t.query(Dialog).map(fn(s) { tenth4(s.rect) })} high \{r(Radio, "高")}")
      }
    }
  }
  // (as main has it, a4c845604; since 2026-11-02 the tall and the crowded open on those used most and starred alone, the
  // rest a step further, room between its parts: Opus not among them)
  assert_eq(out, [
    "newchat-model: dialog Some((648.9, 265.9, 258, 261.6)) opus Some((654.9, 404.8, 246, 34)) high Some((855.9, 448.8, 43, 30))",
    "newchat-tall-model: dialog Some((648.9, 146.9, 520, 380.6)) opus None high Some((943.9, 378.8, 54.3, 30))",
    "newchat-crowded-model: dialog Some((648.9, 195.9, 364, 331.6)) opus None high Some((893.7, 413.8, 55.6, 30))",
    "newchat-crowded-model 低: dialog Some((648.9, 195.9, 364, 331.6)) high Some((893.7, 413.8, 55.6, 30))",
    "newchat-crowded-model 最高: dialog Some((648.9, 195.9, 364, 331.6)) high Some((893.7, 413.8, 55.6, 30))",
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
  "foot 3: dialog Some((600, 106, 74, 104.8)) title [(616, 118, 42, 20)] words [(616, 142, 42, 22)] button Some((611.2, 172, 58, 34)) end None",
  "foot 38: dialog Some((600, 106, 400, 126.8)) title [(616, 118, 368, 20)] words [(616, 142, 368, 44)] button Some((937.2, 194, 58, 34)) end None",
  "foot 8: dialog Some((600, 106, 400, 104.8)) title [(616, 118, 368, 20)] words [(616, 142, 368, 22)] button Some((937.2, 172, 58, 34)) end None",
  "foot 3: dialog Some((600, 106, 400, 104.8)) title [(616, 118, 368, 20)] words [(616, 142, 368, 22)] button Some((937.2, 172, 58, 34)) end None",
  "end 3: dialog Some((600, 106, 103.8, 70.8)) title [(616, 117.8, 26, 20)] words [(616, 148.8, 71.8, 22)] button None end Some((654, 110.8, 45, 34))",
  "end 38: dialog Some((600, 106, 400, 92.8)) title [(616, 117.8, 26, 20)] words [(616, 148.8, 368, 44)] button None end Some((654, 110.8, 341.2, 34))",
  "end 8: dialog Some((600, 106, 400, 70.8)) title [(616, 117.8, 26, 20)] words [(616, 148.8, 368, 22)] button None end Some((654, 110.8, 341.2, 34))",
  "end 3: dialog Some((600, 106, 400, 70.8)) title [(616, 117.8, 26, 20)] words [(616, 148.8, 368, 22)] button None end Some((654, 110.8, 341.2, 34))",
  "narrow 3: dialog Some((600, 106, 103.8, 70.8)) title [(616, 117.8, 26, 20)] words [(616, 148.8, 71.8, 22)] button None end Some((654, 110.8, 45, 34))",
  "narrow 38: dialog Some((600, 106, 200, 136.8)) title [(616, 117.8, 26, 20)] words [(616, 148.8, 168, 88)] button None end Some((654, 110.8, 141.2, 34))",
  "narrow 8: dialog Some((600, 106, 200, 70.8)) title [(616, 117.8, 26, 20)] words [(616, 148.8, 168, 22)] button None end Some((654, 110.8, 141.2, 34))",
  "narrow 3: dialog Some((600, 106, 200, 70.8)) title [(616, 117.8, 26, 20)] words [(616, 148.8, 168, 22)] button None end Some((654, 110.8, 141.2, 34))",
  "column: dialog (600, 90, 74, 402) row0 [(616, 126, 42, 22)] held Some(false) | wheel: [(616, 6, 42, 22)]",
]
