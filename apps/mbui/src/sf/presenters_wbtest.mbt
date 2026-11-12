// The presenters (presenters.mbt), each at the Small tier with a finger (a sheet) and at the Large tier with a mouse
// (the web's: beside what opened it, or in the middle of the window).

///|
/// A phone's window (Small, a finger) and a desktop's (Large, a mouse).
let phone : (Int, Double, Double) = (2, 390.0, 844.0)

///|
let desk : (Int, Double, Double) = (0, 1280.0, 800.0)

///|
test "an anchored panel animates both entering and leaving before its presenter is removed" {
  let t = presenting_tester(desk, fn(from) {
    panel("动画面板", from~, fn(c, _) { c.text("面板内容") |> ignore })
  })
  t.tap_text("打开")
  t.run_for(@kit.pop_ms / 2.0)
  let (_, _, entering) = t.look_of("面板内容").unwrap()
  assert_true(entering > 0.0 && entering < 1.0)
  t.run_for(@kit.pop_ms)
  close_presented()
  t.frame()
  t.run_for(@kit.pop_out_ms / 2.0)
  let (_, _, leaving) = t.look_of("面板内容").unwrap()
  assert_true(leaving > 0.0 && leaving < 1.0)
  t.run_for(@kit.pop_out_ms)
  assert_true(t.look_of("面板内容") is None)
}

///|
/// A page with one button, 打开 (`at` its top, its middle, or its foot as a composer's choices are), that opens what
/// `open` presents (given what opened it), and the host over it.
fn presenting_view(open : (Anchor) -> Unit, at? : @ui.Justify = JStart) -> (@ui.Ctx) -> Unit {
  fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), pad=40.0, justify=at, fn() {
        let from = c.id("open")
        button(c, "打开", key="open", on_press=fn() { open(Of(from)) }) |> ignore
      })
      |> ignore
      presented(c)
    })
  }
}

///|
fn presenting_tester(at : (Int, Double, Double), open : (Anchor) -> Unit, button_at? : @ui.Justify = JStart) -> @ui.Tester {
  presenters_reset()
  // (the words their keys, as these tests press them (`common.cancel`): a file run before this one in the same
  // program may have given the library its own, player_wbtest's table says 取消 for it, and they stay as given)
  set_words(fn(key, _) { key })
  let (platform, w, h) = at
  let t = @ui.Tester::new(@ui.old_views_here, tree=presented_tree(presenting_view(open, at=button_at)), w~, h~, platform~)
  t.draw()
  t
}

///|
/// What opened it as a menu's or a pick's (what presenting_view opened it by: its 打开).
fn beside_of(from : Anchor) -> Beside {
  match from {
    Anchor::Of(id) => Of(id)
    Anchor::At(x, y, w, h) => At(x, y, w, h)
    Unanchored | Node(_) => @halt.saying("a menu or a pick is opened beside what opened it")
  }
}

///|
/// 打开 pressed, and what it opened come in: a sheet risen, else the web's in.
fn open_it(t : @ui.Tester) -> Unit {
  t.tap_text("打开")
  if presented_how == [AsSheet] {
    t.run_for(presented_rest() - t.time())
  } else {
    t.run_for(@kit.presence_in_ms)
  }
}

///|
test "a panel's long list draws its rows in the panel's arrangement" {
  for at in [phone, desk] {
    let seen : Array[Look] = []
    let t = presenting_tester(at, fn(from) {
      panel("账号", from~, tall=0.8, grows=true, fn(c, _) {
        panel_list(c, "accounts", 12, 48.0, fn(i) {
          seen.push(look())
          c.text("账号 " + i.to_string()) |> ignore
        }) |> ignore
      })
    })
    open_it(t)
    t.draw()
    assert_true(!seen.is_empty(), msg="the list draws rows")
    let expected = if at == phone { Narrow } else { Wide }
    for arrangement in seen {
      assert_true(arrangement == expected, msg="each row takes the panel's arrangement")
    }
  }
}

///|
test "a capped sheet measures lists that arrive after it opens" {
  let shown = Ref(false)
  let t = presenting_tester(phone, fn(from) {
    panel("内容", from~, tall=0.8, fn(c, _) {
      button(c, "显示列表", on_press=fn() {
        shown.val = true
      }) |> ignore
      if shown.val {
        panel_list(c, "late-a", 1, 20.0, fn(_) {
          c.box(style=@ui.style(w=Full, h=Fixed(96.0)), fn() { c.text("第一组") |> ignore }) |> ignore
        }) |> ignore
        panel_list(c, "late-b", 1, 20.0, fn(_) {
          c.box(style=@ui.style(w=Full, h=Fixed(80.0)), fn() { c.text("第二组") |> ignore }) |> ignore
        }) |> ignore
      }
    })
  })
  open_it(t)
  t.tap_text("显示列表")
  t.draw()
  assert_true(t.find("第一组") is Some(_))
  assert_true(t.find("第二组") is Some(_))
}

///|
/// Where `words` are drawn, or a failure.
fn where_is(t : @ui.Tester, words : String) -> (Double, Double) raise {
  match t.find(words) {
    Some(at) => at
    None => fail("no \{words}")
  }
}

///|
fn menu_items_of(said : Array[String]) -> Array[MenuItem?] {
  [
    Some(menu_item_of("重命名", fn() { said.push("rename") }, icon="edit")),
    None,
    Some(menu_item_of("删掉", fn() { said.push("delete") }, danger=true)),
  ]
}

///|
test "a menu with a finger at Small: a sheet from the foot; an item tapped closes it and does what it says" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) { menu(menu_items_of(said), from=beside_of(from)) })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  // in the sheet's rows, low in the window
  assert_true(where_is(t, "重命名").1 > phone.2 / 2.0)
  t.tap_text("删掉")
  assert_eq(said, ["delete"])
  assert_true(!presenting())
}

///|
test "a menu with a mouse at Large: beside what opened it; Escape closes it, an item chosen does what it says" {
  let said : Array[String] = []
  let t = presenting_tester(desk, fn(from) { menu(menu_items_of(said), from=beside_of(from)) })
  let (_, by) = where_is(t, "打开")
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  // under the button, not far
  let (_, y) = where_is(t, "重命名")
  assert_true(y > by && y < by + 80.0)
  assert_true(t.key_named("esc"))
  assert_true(!presenting())
  assert_eq(said, [])
  open_it(t)
  t.tap_text("重命名")
  assert_eq(said, ["rename"])
  assert_true(!presenting())
}

///|
/// The colours the glyphs of the first words containing `words` are drawn in (those whose quads start in the words'
/// upper half).
fn inks_of(t : @ui.Tester, words : String) -> Array[Int64] raise {
  let (x, y, w, h) = match t.rect_of(words) {
    Some(r) => r
    None => fail("no \{words}")
  }
  let out = []
  for g in t.drawn_glyphs() {
    if g.0 >= x - 1.0 && g.0 <= x + w + 1.0 && g.1 >= y - 1.0 && g.1 < y + h / 2.0 && !out.contains(g.2) {
      out.push(g.2)
    }
  }
  out
}

///|
test "a confirmation warning is red in both a sheet and a dialog" {
  for at in [phone, desk] {
    let t = presenting_tester(at, fn(from) {
      confirm("分享账号？", "其他 station 会发送请求", "分享账号", fn() {  }, warning="请确认安全访问", from~)
    })
    open_it(t)
    t.run_for(@ui.move_most_ms)
    t.draw()
    let warning_ink = inks_of(t, "请确认安全访问")
    let words_ink = inks_of(t, "其他 station 会发送请求")
    assert_true(warning_ink == [light_palette.red] || warning_ink == [web_light.red], msg="warning at \{Repr(at)}")
    assert_true(words_ink == [light_palette.muted] || words_ink == [web_light.muted], msg="description at \{Repr(at)}")
  }
}

///|
test "a confirmation drawn in the window's tree shows its warning in red" {
  presenters_reset()
  let t = @ui.Tester::new(fn(_c) {  }, w=1280.0, h=800.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    @ui.old(root, fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() { presented(c) })
    }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
  })
  t.draw()
  confirm("分享账号？", "其他 station 会发送请求", "分享账号", fn() {  }, warning="请确认安全访问")
  t.run_for(@ui.move_most_ms)
  t.draw()
  assert_eq(inks_of(t, "请确认安全访问"), [@ui.tree_theme().color(Danger)])
  assert_eq(inks_of(t, "其他 station 会发送请求"), [@ui.tree_theme().color(Muted)])
}

///|
test "a menu with a mouse at Large: an item not to be chosen now in the subtle ink (it is never lit), clicked does nothing" {
  let said : Array[String] = []
  let items = [
    Some(menu_item_of("重命名", fn() { said.push("rename") }, icon="edit")),
    Some(menu_item_of("启动", fn() { said.push("start") }, icon="play", disabled=true)),
  ]
  let t = presenting_tester(desk, fn(from) { menu(items, from=beside_of(from)) })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  let p = theme().p
  assert_eq(inks_of(t, "启动"), [p.subtle])
  assert_eq(inks_of(t, "重命名"), [p.text])
  t.tap_text("启动")
  assert_eq(said, [])
  assert_true(presenting())
}

///|
/// Choices to pick from, `n` of them: 第1项 … 第n项, known as c1 … cn. (No words are told in a test: a key is said
/// as it is, common.search.)
fn choices_of(n : Int) -> Array[Choice] {
  Array::makei(n, fn(i) { choice("c\{i + 1}", "第\{i + 1}项", note=if i == 0 { "最近用过" } else { "" }) })
}

///|
test "a pick with a finger at Small: a sheet of the choices; one tapped is chosen and it closes" {
  let chosen = Ref("c1")
  let t = presenting_tester(phone, fn(from) { pick("选一个", choices_of(3), chosen.val, fn(k) { chosen.val = k }, from=beside_of(from)) })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  assert_true(t.find("选一个") is Some(_))
  assert_true(t.find("最近用过") is Some(_))
  t.tap_text("第3项")
  assert_eq(chosen.val, "c3")
  assert_true(!presenting())
}

///|
test "a long pick with a mouse at Large: its search over it finds by the words, Enter picks the first found" {
  let chosen = Ref("c1")
  let t = presenting_tester(desk, fn(from) {
    pick("选一个", choices_of(pick_search_from + 4), chosen.val, fn(k) { chosen.val = k }, from=beside_of(from))
  })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  assert_true(t.find("第2项") is Some(_))
  t.type_text("第11")
  // (what no longer matches closing its room, gone once it has)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第2项") is None)
  assert_true(t.find("第11项") is Some(_))
  t.type_text("x")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("common.noMatch") is Some(_))
  t.backspace()
  t.run_for(@ui.move_most_ms)
  assert_true(t.key_named("enter"))
  assert_eq(chosen.val, "c11")
  assert_true(!presenting())
}

///|
test "a long pick with a finger at Small: the search in its sheet finds by the words" {
  let chosen = Ref("c1")
  let t = presenting_tester(phone, fn(from) {
    pick("选一个", choices_of(pick_search_from + 4), chosen.val, fn(k) { chosen.val = k }, from=beside_of(from))
  })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  t.tap_text("common.search")
  t.type_text("第12")
  assert_true(t.find("第3项") is None)
  t.tap_text("第12项")
  assert_eq(chosen.val, "c12")
}

///|
/// A panel: its words, and a button at its foot that closes it (a small panel's: PanelText, PanelFoot, PanelButton).
fn panel_body(said : Array[String]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, close) {
    panel_text(c, fn() { c.text("面板里的话", style=paragraph) |> ignore })
    panel_foot(c, fn() {
      panel_button(c, "ok", "好的", tone=Filled, on_press=fn() {
        said.push("ok")
        close()
      }) |> ignore
    })
  }
}

///|
test "a panel with a finger at Small: a sheet; back closes it" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) { panel("面板", panel_body(said), from~) })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  assert_true(t.find("面板里的话") is Some(_))
  t.back()
  assert_true(!presenting())
  open_it(t)
  t.tap_text("好的")
  assert_eq(said, ["ok"])
  assert_true(!presenting())
}

///|
test "a panel with a mouse at Large: beside what opened it; a press outside closes it" {
  let said : Array[String] = []
  let t = presenting_tester(desk, fn(from) { panel("面板", panel_body(said), from~) })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  let (_, by) = where_is(t, "打开")
  assert_true(where_is(t, "面板").1 > by)
  t.tap(desk.1 - 40.0, desk.2 - 40.0)
  assert_true(!presenting())
  assert_eq(said, [])
}

///|
/// A panel's body of `n` lines (第1行 … 第n行), saying in `held` whether it was drawn held short of them (panel_held).
fn lines_body(n : Int, held : Ref[Bool]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, _) {
    held.val = panel_held()
    for i in 1..=n {
      c.text("第\{i}行", style=paragraph) |> ignore
    }
  }
}

///|
/// A panel's foot: 好的, which says so and closes it.
fn ok_foot(said : Array[String]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, close) {
    button(c, "好的", key="ok", tone=Primary, on_press=fn() {
      said.push("ok")
      close()
    }) |> ignore
  }
}

///|
test "a sheet's action buttons keep their words whole, sharing the row or going onto another" {
  for (first, second, separate, disabled) in [
    ("取消", "添加到此 workspace", false, false),
    ("取消", "添加到此 workspace", false, true),
    ("Doesn't match, deny", "Turn off security mode", true, false),
  ] {
    let t = presenting_tester((2, 320.0, 844.0), fn(from) {
      panel("Actions", from~, fn(c, _) { c.text("Content") |> ignore }, foot=fn(c, _) {
        button(c, first, key="first") |> ignore
        button(c, second, key="second", tone=Primary, disabled~) |> ignore
      })
    })
    open_it(t)
    assert_eq(t.lines_of(first), [first], msg="first: \{Repr(t.lines_of(first))}")
    assert_eq(t.lines_of(second), [second], msg="second: \{Repr(t.lines_of(second))}")
    let a = t.rect_of(first).unwrap()
    let b = t.rect_of(second).unwrap()
    if separate {
      assert_true(b.1 >= a.1 + a.3, msg="buttons overlap: \{Repr(a)}, \{Repr(b)}")
    } else {
      assert_true((a.1 - b.1).abs() < 1.0, msg="the buttons fit side by side: \{Repr(a)}, \{Repr(b)}")
    }
  }
}

///|
/// Where `words` are drawn now (their top and bottom, moved as what holds them scrolls), or a failure.
fn drawn_span(t : @ui.Tester, words : String) -> (Double, Double) raise {
  match t.words().iter().find_first(fn(w) { w.0 == words }) {
    Some((_, _, y, _, h, _)) => (y, y + h)
    None => fail("\{words} not drawn")
  }
}

///|
test "a panel with a mouse beside what opened it, as tall as what it holds where that fits: not held" {
  let held = Ref(true)
  let t = presenting_tester(desk, fn(from) { panel("面板", lines_body(3, held), from~, foot=ok_foot([])) })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  assert_true(!held.val)
  // its foot right under what it holds
  let (_, last) = drawn_span(t, "第3行")
  let (foot, _) = drawn_span(t, "好的")
  assert_true(foot > last && foot < last + 60.0)
}

///|
test "a panel with a mouse opened at the window's foot, with the room over it: over it, as tall as what it holds" {
  let held = Ref(true)
  let short = (0, 1280.0, 360.0)
  let t = presenting_tester(short, fn(from) { panel("面板", lines_body(3, held), from~, foot=ok_foot([])) }, button_at=JEnd)
  let (_, by) = where_is(t, "打开")
  open_it(t)
  let (_, bottom) = drawn_span(t, "好的")
  assert_true(bottom < by, msg="not over what opened it")
  assert_true(!held.val)
}

///|
test "a panel with a mouse taller than the room on either side of what opened it, not than the window: moved over it to stay in, as tall as what it holds" {
  let held = Ref(true)
  let mid = (0, 1280.0, 400.0)
  let t = presenting_tester(mid, fn(from) { panel("面板", lines_body(10, held), from~, foot=ok_foot([])) }, button_at=JCenter)
  let (_, by) = where_is(t, "打开")
  open_it(t)
  // all of it in the window, over the button rather than shortened
  let (top, _) = drawn_span(t, "面板")
  let (_, bottom) = drawn_span(t, "好的")
  assert_true(top > 0.0 && bottom < mid.2, msg="out of the window")
  assert_true(top < by && bottom > by, msg="not moved over what opened it")
  assert_true(!held.val, msg="shortened while the window has the room for it")
  assert_true(drawn_span(t, "第10行").1 < bottom)
}

///|
test "a panel with a mouse taller than the window: as tall as the window lets it, its title and foot in it, what it holds scrolled to" {
  let said : Array[String] = []
  let held = Ref(false)
  let short = (0, 1280.0, 320.0)
  let t = presenting_tester(short, fn(from) { panel("面板", lines_body(40, held), from~, foot=ok_foot(said)) })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  let (top, _) = drawn_span(t, "面板")
  let (_, bottom) = drawn_span(t, "好的")
  assert_true(top > 0.0, msg="its title out of the window")
  assert_true(bottom < short.2, msg="its foot out of the window")
  assert_true(held.val, msg="what it holds not told it scrolls as one")
  // its last line under the foot until what it holds is scrolled, then over it
  let (foot, _) = drawn_span(t, "好的")
  assert_true(drawn_span(t, "第40行").0 > foot)
  let (lx, ly) = where_is(t, "第1行")
  t.wheel(lx, ly, 2000.0)
  assert_true(drawn_span(t, "第40行").1 < foot, msg="what it holds not scrolled to its end")
  assert_true(drawn_span(t, "面板").0 == top, msg="its title scrolled with what it holds")
  t.tap_text("好的")
  assert_eq(said, ["ok"])
  assert_true(!presenting())
}

///|
test "a confirm with a finger at Small: a sheet; its action does it, the cancel does not" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) {
    confirm("归档这个对话？", "归档后仍可在归档里找到。", "确认归档", fn() { said.push("archived") }, danger=true, from~)
  })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  t.tap_text("common.cancel")
  assert_eq(said, [])
  assert_true(!presenting())
  open_it(t)
  t.tap_text("确认归档")
  assert_eq(said, ["archived"])
  assert_true(!presenting())
}

///|
test "a confirm with a mouse at Large: a dialog in the middle of the window; Escape closes it, its action does it" {
  let said : Array[String] = []
  let t = presenting_tester(desk, fn(from) {
    confirm("归档这个对话？", "归档后仍可在归档里找到。", "确认归档", fn() { said.push("archived") }, from~)
  })
  open_it(t)
  assert_eq(presented_how, [AsDialog])
  let (x, _) = where_is(t, "归档后仍可在归档里找到。")
  assert_true(x > desk.1 / 2.0 - confirm_w / 2.0 && x < desk.1 / 2.0 + confirm_w / 2.0)
  assert_true(t.key_named("esc"))
  assert_true(!presenting())
  open_it(t)
  t.tap_text("确认归档")
  assert_eq(said, ["archived"])
  assert_true(!presenting())
}

///|
test "a question with a finger at Small: a sheet with its line; its action, once the line differs, goes on with it" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) {
    ask("重命名", "保存", fn(line) { said.push(line) }, value="旧名字", from~)
  })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  // the same line as it was: nothing to save
  t.tap_text("保存")
  assert_eq(said, [])
  t.type_text(" 新的 ")
  t.tap_text("保存")
  assert_eq(said, ["旧名字 新的"])
  assert_true(!presenting())
}

///|
test "a question with a mouse at Large: a dialog with its line; Enter says it" {
  let said : Array[String] = []
  let t = presenting_tester(desk, fn(from) { ask("重命名", "保存", fn(line) { said.push(line) }, placeholder="名字", from~) })
  open_it(t)
  assert_eq(presented_how, [AsDialog])
  assert_true(t.key_named("enter"))
  assert_eq(said, [])
  t.type_text("新名字")
  assert_true(t.key_named("enter"))
  assert_eq(said, ["新名字"])
  assert_true(!presenting())
}

///|
test "one over another: a confirm from a menu's item comes when the menu has gone; back closes the topmost first" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) {
    panel("面板", fn(c, _) {
      button(c, "删除它", key="del", on_press=fn() {
        confirm("删掉吗？", "删掉后不能恢复。", "删掉", fn() { said.push("deleted") }, danger=true)
      }) |> ignore
    }, from~)
  })
  open_it(t)
  t.tap_text("删除它")
  t.run_for(presented_rest() - t.time())
  assert_eq(presented_how, [AsSheet, AsSheet])
  t.back()
  assert_eq(presented_how, [AsSheet])
  t.back()
  assert_true(!presenting())
  assert_eq(said, [])
}

///|
/// A panel opened by nothing (a form's dialog): its words, its foot's button closing it as said; what it lets go of
/// as it closes unsaid.
fn dialog_panel(said : Array[String]) -> (Anchor) -> Unit {
  fn(_) {
    panel(
      "添加一项",
      fn(c, _) { c.text("填好下面的内容", style=paragraph) |> ignore },
      from=Unanchored,
      description="每项都会加密保存",
      foot=fn(c, close) {
        button(c, "确认添加", key="add", on_press=fn() {
          said.push("added")
          close()
        }) |> ignore
      },
      gone=fn() { said.push("gone") },
    )
  }
}

///|
/// How many grounds over the whole window dim what is under them in the last frame (`at`'s window).
fn scrims_drawn(t : @ui.Tester, at : (Int, Double, Double)) -> Int {
  let (_, w, h) = at
  t
  .drawn_rects()
  .filter(fn(r) { r.0 <= 0.0 && r.1 <= 0.0 && r.2 >= w && r.3 >= h && (r.4 & 0xFFL) > 0L && (r.4 & 0xFFL) < 0xFFL })
  .length()
}

///|
/// Whether something less than the window is dimmed over itself in the last frame, in the colour the window is dimmed
/// with (a dialog with another over it).
fn veiled_drawn(t : @ui.Tester, at : (Int, Double, Double)) -> Bool {
  veiled_in(t.drawn_rects(), at.1, at.2)
}

///|
/// Whether of `rects` one less than the window (`w` by `h`) is drawn in the colour one over all of it dims it with.
fn veiled_in(rects : Array[(Double, Double, Double, Double, Int64)], w : Double, h : Double) -> Bool {
  let see_through = fn(c : Int64) { (c & 0xFFL) > 0L && (c & 0xFFL) < 0xFFL }
  match rects.iter().find_first(fn(r) { r.0 <= 0.0 && r.1 <= 0.0 && r.2 >= w && r.3 >= h && see_through(r.4) }) {
    Some(scrim) => rects.iter().any(fn(r) { (r.2 < w || r.3 < h) && see_through(r.4) && (r.4 >> 8) == (scrim.4 >> 8) })
    None => false
  }
}

///|
/// A panel (opened by 打开, `from` it or by nothing) with 删掉 in it, which asks a confirm over it.
fn panel_with_confirm(at : (Int, Double, Double), by_nothing? : Bool = false) -> @ui.Tester {
  presenting_tester(at, fn(from) {
    panel(
      "面板",
      from=if by_nothing { Unanchored } else { from },
      fn(c, _) {
        c.text("面板内容") |> ignore
        button(c, "删掉", key="drop", on_press=fn() {
          confirm("删掉这个？", "删掉后找不回来。", "确认删掉", fn() {  }, danger=true)
        }) |> ignore
      },
    )
  })
}

///|
test "one over another with a finger at Small: one scrim however many sheets, the one under pushed up out of the way and down again" {
  let t = panel_with_confirm(phone)
  open_it(t)
  assert_eq(scrims_drawn(t, phone), 1)
  let (_, y0) = t.drawn_of("面板内容").unwrap()
  t.tap_text("删掉")
  t.run_for(presented_rest() - t.time())
  t.run_for(@ui.move_most_ms)
  assert_eq(presented_how, [AsSheet, AsSheet])
  // (no darker for the second: the one under dims, the one over it not)
  assert_eq(scrims_drawn(t, phone), 1)
  // (the one under pushed up out of its way, whole over it, not laid under it: its words over the confirm's title)
  let (_, y1) = t.drawn_of("面板内容").unwrap()
  let (_, title) = t.drawn_of("删掉这个？").unwrap()
  assert_true(y1 < y0 - pushed_gap && y1 < title, msg="\{y0} \{y1} \{title}")
  // (the two not laid one over the other: the one under ends, foot and all, pushed_gap over the one over it)
  let sheets = t.drawn_glass().copy()
  sheets.sort_by_key(fn(g) { g.1 })
  assert_eq(sheets.length(), 2, msg="\{Repr(sheets)}")
  assert_true(sheets[0].1 + sheets[0].3 + pushed_gap <= sheets[1].1 + 0.5, msg="\{Repr(sheets)}")
  // (the one under taking nothing while it is up: dimmed over itself as the window is, not the window twice)
  assert_true(
    t.drawn_rects().iter().any(fn(r) { r.4 == sheet_scrim && r.3 < phone.2 }),
    msg="\{Repr(t.drawn_rects().filter(fn(r) { (r.4 & 0xFFL) < 0xFFL }))}",
  )
  // (the one over it gone: the one under forward again, its scrim as it was all along)
  t.back()
  t.run_for(presented_rest() - t.time())
  t.run_for(@ui.move_most_ms)
  assert_eq(presented_how, [AsSheet])
  assert_eq(scrims_drawn(t, phone), 1)
  let (_, y2) = t.drawn_of("面板内容").unwrap()
  assert_true((y2 - y0).abs() < 0.5, msg="\{y0} \{y2}")
}

///|
/// The one sheet drawn in the last frame: its top and how tall (a failure where there is none, or more).
fn one_sheet(t : @ui.Tester) -> (Double, Double) raise {
  let sheets = t.drawn_glass().filter(fn(g) { g.3 > 100.0 })
  guard sheets.length() == 1 else { fail("\{sheets.length()} sheets: \{Repr(sheets)}") }
  (sheets[0].1, sheets[0].3)
}

///|
/// How dark the ground over the whole window dims what is under it in the last frame (`at`'s window; 0: none does).
fn scrim_alpha(t : @ui.Tester, at : (Int, Double, Double)) -> Int64 {
  let (_, w, h) = at
  t.drawn_rects().iter().filter(fn(r) { r.0 <= 0.0 && r.1 <= 0.0 && r.2 >= w && r.3 >= h && (r.4 & 0xFFL) < 0xFFL }).fold(
    init=0L,
    fn(a, r) { a + (r.4 & 0xFFL) },
  )
}

///|
/// A menu (重命名, 归档, 固定, 分享…) whose 分享… opens a menu from the same place, 分享 (复制链接, 分享图片): each said as
/// it is chosen, `gone` and `level gone` as each is let go of with nothing chosen.
fn menu_with_more(said : Array[String]) -> (Anchor) -> Unit {
  fn(from) {
    let beside = beside_of(from)
    menu(
      [
        Some(menu_item_of("重命名", fn() { said.push("rename") })),
        Some(menu_item_of("归档", fn() { said.push("archive") })),
        Some(menu_item_of("固定", fn() { said.push("pin") })),
        Some(
          menu_item_of("分享…", fn() {
            menu(
              [
                Some(menu_item_of("复制链接", fn() { said.push("copy") })),
                Some(menu_item_of("分享图片", fn() { said.push("image") })),
              ],
              from=beside,
              title="分享",
              gone=fn() { said.push("level gone") },
            )
          }),
        ),
      ],
      from=beside,
      gone=fn() { said.push("gone") },
    )
  }
}

///|
/// The frames a sheet's way takes at most, each looked at.
let way_frames : Int = 40

///|
test "a menu's item that opens a menu, with a finger at Small: a level of the same sheet, one sheet and the scrim as it was all the way; back is back to the menu" {
  let said : Array[String] = []
  let t = presenting_tester(phone, menu_with_more(said))
  open_it(t)
  let (top0, _) = one_sheet(t)
  let dim = scrim_alpha(t, phone)
  assert_true(dim > 0L)
  t.tap_text("分享…")
  // (the frame it was chosen in: the menu's sheet where it stood, the window as dim; nothing let go of)
  assert_eq(presented_how, [AsSheet])
  assert_true((one_sheet(t).0 - top0).abs() < 0.5, msg="\{Repr(one_sheet(t))} \{top0}")
  assert_eq(scrim_alpha(t, phone), dim)
  // (on its way to the level's height, shorter: down only, never two sheets, the window never brighter)
  let mut last = top0
  for _ in 0..<way_frames {
    t.run_for(@ui.frame_period_default)
    let (top, _) = one_sheet(t)
    assert_eq(scrim_alpha(t, phone), dim)
    assert_true(top >= last - 0.5, msg="\{top} after \{last}")
    last = top
  }
  assert_true(last > top0 + 20.0, msg="\{last} \{top0}")
  assert_true(t.find("复制链接") is Some(_) && t.find("重命名") is None)
  // (its title over its rows)
  assert_true(where_is(t, "分享").1 < where_is(t, "复制链接").1)
  assert_eq(said, [])
  // back: the menu again, as tall as it was; the level let go of, the menu not
  t.back()
  assert_true(presenting())
  for _ in 0..<way_frames {
    t.run_for(@ui.frame_period_default)
    one_sheet(t) |> ignore
    assert_eq(scrim_alpha(t, phone), dim)
  }
  assert_true(t.find("重命名") is Some(_) && t.find("复制链接") is None)
  assert_true((one_sheet(t).0 - top0).abs() < 0.5, msg="\{Repr(one_sheet(t))} \{top0}")
  assert_eq(said, ["level gone"])
  t.back()
  assert_true(!presenting())
  t.run_for(@ui.move_most_ms)
  assert_eq(said, ["level gone", "gone"])
  // chosen in the level: done, all of it closed, nothing let go of unsaid
  open_it(t)
  t.tap_text("分享…")
  t.run_for(@ui.move_most_ms)
  t.tap_text("复制链接")
  assert_true(!presenting())
  t.run_for(@ui.move_most_ms)
  assert_eq(said, ["level gone", "gone", "copy"])
}

///|
test "a menu's item that opens a menu, with a mouse at Large: the next menu beside what opened it, the first gone" {
  let said : Array[String] = []
  let t = presenting_tester(desk, menu_with_more(said))
  open_it(t)
  t.tap_text("分享…")
  t.run_for(@kit.presence_in_ms)
  assert_eq(presented_how, [AsPopover])
  assert_true(t.find("复制链接") is Some(_))
  assert_true(t.key_named("esc"))
  assert_true(!presenting())
  assert_eq(said, ["level gone"])
}

///|
test "what a sheet's item opens with a finger at Small: a sheet in its place, from as tall as that one stood, the scrim as it was, never two" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) {
    menu(
      [
        Some(menu_item_of("重命名", fn() { ask("重命名", "保存", fn(line) { said.push(line) }, value="旧名字", from~) })),
        Some(menu_item_of("归档", fn() { said.push("archive") })),
        Some(menu_item_of("固定", fn() { said.push("pin") })),
        Some(menu_item_of("静音", fn() { said.push("mute") })),
        Some(menu_item_of("隐藏", fn() { said.push("hide") })),
        Some(
          menu_item_of(
            "删掉",
            fn() { confirm("删掉吗？", "删掉后不能恢复。", "删掉它", fn() { said.push("deleted") }, danger=true, from~) },
            danger=true,
          ),
        ),
      ],
      from=beside_of(from),
    )
  })
  for opened in [("删掉", "删掉吗？", "删掉它"), ("重命名", "保存", "保存")] {
    let (item, words, action) = opened
    open_it(t)
    let (top0, _) = one_sheet(t)
    let dim = scrim_alpha(t, phone)
    assert_true(dim > 0L)
    t.tap_text(item)
    // (the frame it was chosen in: what it opened where the menu stood, the menu gone, the window as dim)
    assert_eq(presented_how, [AsSheet], msg=item)
    assert_true((one_sheet(t).0 - top0).abs() < 0.5, msg="\{item}: \{Repr(one_sheet(t))} \{top0}")
    assert_eq(scrim_alpha(t, phone), dim, msg=item)
    assert_true(t.find(words) is Some(_) && t.find("归档") is None, msg=item)
    // (on its way to its own height, shorter: down only, never two sheets, the window never brighter)
    let mut last = top0
    for _ in 0..<way_frames {
      t.run_for(@ui.frame_period_default)
      let (top, _) = one_sheet(t)
      assert_eq(scrim_alpha(t, phone), dim, msg=item)
      assert_true(top >= last - 0.5, msg="\{item}: \{top} after \{last}")
      last = top
    }
    assert_true(last > top0 + 20.0, msg="\{item}: \{last} \{top0}")
    // (as tall as what it holds: its action over the window's foot)
    assert_true(where_is(t, action).1 < phone.2, msg=item)
    t.back()
    assert_true(!presenting(), msg=item)
    t.run_for(@ui.move_most_ms)
  }
  assert_eq(said, [])
}

///|
/// A panel, 信息 (opened by 打开, by nothing), whose 看详情 closes it and opens another, 详情: each `gone` said as it is
/// let go of unsaid.
fn panel_with_more(said : Array[String]) -> (Anchor) -> Unit {
  fn(_) {
    panel(
      "信息",
      fn(c, close) {
        c.text("信息内容") |> ignore
        c.text("信息的第二行") |> ignore
        c.text("信息的第三行") |> ignore
        button(c, "看详情", key="more", on_press=fn() {
          close()
          panel("详情", fn(c, _) { c.text("详情内容") |> ignore }, from=Unanchored, gone=fn() { said.push("detail gone") })
        })
      },
      from=Unanchored,
      gone=fn() { said.push("info gone") },
    )
  }
}

///|
test "a panel a panel's button opens as it closes, with a finger at Small: a step further in, in its place; back is back to the first, a press outside closes all" {
  let said : Array[String] = []
  let t = presenting_tester(phone, panel_with_more(said))
  open_it(t)
  let (top0, _) = one_sheet(t)
  let dim = scrim_alpha(t, phone)
  assert_true(dim > 0L)
  t.tap_text("看详情")
  // (the frame it was pressed in: the next where the first stood, the window as dim)
  assert_eq(presented_how, [AsSheet])
  assert_true((one_sheet(t).0 - top0).abs() < 0.5, msg="\{Repr(one_sheet(t))} \{top0}")
  assert_eq(scrim_alpha(t, phone), dim)
  // (a page of the same sheet: sliding in over the first, which slides off)
  assert_true(t.find("详情内容") is Some(_))
  for _ in 0..<way_frames {
    t.run_for(@ui.frame_period_default)
    one_sheet(t) |> ignore
    assert_eq(scrim_alpha(t, phone), dim)
  }
  assert_true(t.find("信息内容") is None)
  let (top1, _) = one_sheet(t)
  assert_true(top1 > top0 + 10.0, msg="\{top1} \{top0}")
  assert_eq(said, [])
  // back: the first again where this one stood, on to as tall as it was; this one let go of, the first not
  t.back()
  assert_true(presenting())
  assert_true(t.find("信息内容") is Some(_))
  assert_true((one_sheet(t).0 - top1).abs() < 0.5, msg="\{Repr(one_sheet(t))} \{top1}")
  assert_eq(scrim_alpha(t, phone), dim)
  for _ in 0..<way_frames {
    t.run_for(@ui.frame_period_default)
    one_sheet(t) |> ignore
    assert_eq(scrim_alpha(t, phone), dim)
  }
  assert_true((one_sheet(t).0 - top0).abs() < 0.5, msg="\{Repr(one_sheet(t))} \{top0}")
  assert_eq(said, ["detail gone"])
  // in again and back again, then back from the first: closed
  t.tap_text("看详情")
  t.run_for(@ui.move_most_ms)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("信息内容") is Some(_))
  t.back()
  assert_true(!presenting())
  t.run_for(@ui.move_most_ms)
  assert_eq(said, ["detail gone", "detail gone", "info gone"])
  // a press outside the step further in: all of it closed
  open_it(t)
  t.tap_text("看详情")
  t.run_for(@ui.move_most_ms)
  t.tap(phone.1 / 2.0, 40.0)
  assert_true(!presenting())
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("信息内容") is None && t.find("详情内容") is None)
}

///|
test "a panel a panel's button opens as it closes, with a mouse at Large: a step further in, a dialog with a back key; its back key and Escape are back to the first, a press outside closes all" {
  let said : Array[String] = []
  let t = presenting_tester(desk, panel_with_more(said))
  open_it(t)
  t.tap_text("看详情")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("详情内容") is Some(_) && t.find("信息内容") is None)
  // its back key, before its title: back to the first
  t.click(Button, label="common.back")
  t.run_for(@kit.presence_in_ms)
  assert_true(presenting())
  assert_true(t.find("信息内容") is Some(_) && t.find("详情内容") is None)
  assert_eq(said, ["detail gone"])
  // (the first has none: nothing before it)
  assert_true(t.query(Button, label="common.back") is None)
  // Escape: back to the first, then closed
  t.tap_text("看详情")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.key_named("esc"))
  t.run_for(@kit.presence_in_ms)
  assert_true(presenting() && t.find("信息内容") is Some(_))
  assert_true(t.key_named("esc"))
  assert_true(!presenting())
  assert_eq(said, ["detail gone", "detail gone", "info gone"])
  // a press outside the step further in: all of it closed
  open_it(t)
  t.tap_text("看详情")
  t.run_for(@kit.presence_in_ms)
  t.tap(8.0, 8.0)
  assert_true(!presenting())
}

///|
/// Each kind of presenter, presented by what `from` opened: what in it is called `word` (a menu's item, a pick's
/// choice, a confirm's and a question's action, a button in a panel of an old body, of nodes, of nodes a share of the
/// window tall) closes it and does `then`.
fn kinds_of(from : Anchor, word : String, then : () -> Unit) -> Array[(String, () -> Unit)] {
  let beside = beside_of(from)
  [
    ("a menu", fn() { menu([Some(menu_item_of("别的", fn() {  })), Some(menu_item_of(word, then))], from=beside) }),
    ("a pick", fn() { pick("选一个", [choice("a", "别的"), choice("b", word)], "a", fn(_) { then() }, from=beside) }),
    ("a confirm", fn() { confirm("确定吗？", "这里说明它做什么。", word, then, from~) }),
    ("a question", fn() { ask("写一句", word, fn(_) { then() }, empty=true, from~) }),
    (
      "a panel",
      fn() {
        panel(
          "面板",
          fn(c, close) {
            c.text("面板里的内容") |> ignore
            button(c, word, key="then", on_press=fn() {
              close()
              then()
            })
          },
          from=Unanchored,
        )
      },
    ),
    (
      "a panel of nodes",
      fn() {
        panel_nodes(
          "节点面板",
          fn(v, close) {
            button_node(v, fn() { word }, fn() {
              close()
              then()
            })
            |> ignore
          },
          from=Unanchored,
        )
      },
    ),
    (
      "a tall panel of nodes",
      fn() {
        panel_nodes(
          "高的节点面板",
          fn(v, close) {
            button_node(v, fn() { word }, fn() {
              close()
              then()
            })
            |> ignore
          },
          from=Unanchored,
          tall=0.6,
        )
      },
    ),
  ]
}

///|
test "with a finger at Small, whatever kind of sheet closes for whatever kind: that one in its place where the first stood, one sheet and the scrim as it was on every frame" {
  let kinds = kinds_of(At(0.0, 0.0, 0.0, 0.0), "", fn() {  }).length()
  for i in 0..<kinds {
    for j in 0..<kinds {
      let named : Ref[String] = Ref("")
      let t = presenting_tester(phone, fn(from) {
        let nexts = kinds_of(from, "完成", fn() {  })
        let firsts = kinds_of(from, "下一步", nexts[j].1)
        named.val = "\{firsts[i].0}, then \{nexts[j].0}"
        (firsts[i].1)()
      })
      t.tap_text("打开")
      t.run_for(@ui.move_most_ms + @kit.sheet_scrim_ms)
      let at = named.val
      let first = t.drawn_glass().filter(fn(g) { g.3 > 100.0 })
      assert_eq(first.length(), 1, msg="\{at}: the first: \{Repr(first)}")
      let top0 = first[0].1
      let dim = scrim_alpha(t, phone)
      assert_true(dim > 0L, msg=at)
      // (a question's action said once its line has words)
      if at.has_prefix("a question") {
        t.type_text("一句")
      }
      t.tap_text("下一步")
      // (the frame it was chosen in, and every frame of its way: one sheet, the window as dim; in that frame where the
      // first stood)
      for k in 0..<way_frames {
        let sheets = t.drawn_glass().filter(fn(g) { g.3 > 100.0 })
        assert_eq(sheets.length(), 1, msg="\{at}, frame \{k}: \{Repr(sheets)}")
        assert_eq(scrim_alpha(t, phone), dim, msg="\{at}, frame \{k}")
        if k == 0 {
          assert_true((sheets[0].1 - top0).abs() < 0.5, msg="\{at}: \{sheets[0].1} where the first stood \{top0}")
        }
        t.run_for(@ui.frame_period_default)
      }
      assert_true(t.find("完成") is Some(_), msg=at)
      // closed, however many steps back that is
      for _ in 0..<3 {
        if presenting() {
          t.back()
          t.run_for(@ui.move_most_ms + @kit.sheet_scrim_ms)
        }
      }
      assert_true(!presenting(), msg=at)
    }
  }
}

///|
test "one over another with a mouse at Large: a confirm over a dialog dims no darker" {
  let t = panel_with_confirm(desk, by_nothing=true)
  open_it(t)
  assert_eq(presented_how, [AsDialog])
  assert_eq(scrims_drawn(t, desk), 1)
  t.tap_text("删掉")
  t.run_for(@kit.presence_in_ms)
  assert_eq(presented_how, [AsDialog, AsDialog])
  assert_eq(scrims_drawn(t, desk), 1)
  // (the dialog under it taking nothing: dimmed over itself, as the window is)
  t.run_for(confirm_ground_ms)
  assert_true(veiled_drawn(t, desk), msg="\{Repr(t.drawn_rects())}")
  // (the confirm closed: the dialog's scrim as it was all along, none fading over it)
  assert_true(t.key_named("esc"))
  t.run_for(@kit.presence_in_ms)
  assert_eq(scrims_drawn(t, desk), 1)
}

///|
test "a panel opened by nothing with a mouse at Large: a dialog in the middle; Escape lets go of it, its foot says it" {
  let said : Array[String] = []
  let t = presenting_tester(desk, dialog_panel(said))
  open_it(t)
  assert_eq(presented_how, [AsDialog])
  assert_true(t.find("每项都会加密保存") is Some(_))
  let (x, _) = where_is(t, "填好下面的内容")
  assert_true(x > desk.1 / 2.0 - dialog_w / 2.0 && x < desk.1 / 2.0 + dialog_w / 2.0)
  assert_true(t.key_named("esc"))
  assert_true(!presenting())
  assert_eq(said, ["gone"])
  open_it(t)
  t.tap_text("确认添加")
  assert_true(!presenting())
  assert_eq(said, ["gone", "added"])
}

///|
test "a panel opened by nothing with a finger at Small: a sheet with its words and its foot" {
  let said : Array[String] = []
  let t = presenting_tester(phone, dialog_panel(said))
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  assert_true(t.find("每项都会加密保存") is Some(_))
  t.tap_text("确认添加")
  assert_eq(said, ["added"])
  assert_true(!presenting())
}

///|
test "a short pick with a mouse at Large: a menu of choices beside what opened it, the chosen checked; one clicked" {
  let chosen = Ref("c1")
  let t = presenting_tester(desk, fn(from) { pick("选一个", choices_of(3), chosen.val, fn(k) { chosen.val = k }, from=beside_of(from)) })
  let (_, by) = where_is(t, "打开")
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  let (_, y) = where_is(t, "第1项")
  assert_true(y > by && y < by + 80.0)
  // its note at its end
  assert_true(t.find("最近用过") is Some(_))
  t.tap_text("第2项")
  assert_eq(chosen.val, "c2")
  assert_true(!presenting())
}
