// What a field offers as it is typed in (offers_node), held to what the old @ menu under the relay's note and over the
// composer kept (kit's popover with its focus left in the field, Ctx::on_key before the field): under the field and as
// wide, the focus in the field all the while; ↓ ↑ round, Enter and Tab take the one chosen, closed they are the
// field's; the pointer moving onto a row chooses it; ↓ ↑ bring the one chosen into sight; Escape and a press outside
// close it alone; one taken, the next key is not its.

///|
/// What an offers tester holds: the Tester, the field's frame, what is open, the one chosen, what was taken, how
/// often it was closed, Escapes that reached the window, the field's Enters, presses of the button under it.
priv struct OffersAt {
  t : @ui.Tester
  frame : Ref[@view.View?]
  open : @signals.Signal[Bool]
  current : @signals.Signal[Int]
  taken : Array[Int]
  closes : Ref[Int]
  escapes : Ref[Int]
  sent : Ref[Int]
  under : Ref[Int]
  field : @ui.Field
}

///|
/// A window with the offers' keys (offers_bindings), a field 300 wide 100 in and 100 down, a button 下面 beside it, and
/// what the field offers (`n` of them, 甲 乙 丙, then 第3 …), opened once the field has the focus.
fn offers_tester(n? : Int = 3) -> OffersAt raise {
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0, platform=0)
  let names = ["甲", "乙", "丙"]
  let keys = Array::makei(n, fn(i) { "k\{i}" })
  let named : Map[String, String] = Map([])
  for i, k in keys {
    named[k] = if i < names.length() { names[i] } else { "第\{i}" }
  }
  let name_of = fn(k : String) { named.get(k).unwrap_or(k) }
  let x : OffersAt = {
    t,
    frame: Ref(None),
    open: @signals.signal(false, same=fn(a, b) { a == b }),
    current: @signals.signal(0, same=fn(a, b) { a == b }),
    taken: [],
    closes: Ref(0),
    escapes: Ref(0),
    sent: Ref(0),
    under: Ref(0),
    field: @ui.Field::new(),
  }
  @ui.set_view_app(fn(root) {
    root
    .keymap(Is(@view.Keymap::new(offers_bindings())))
    .row(Is(true))
    .padding(Is((100.0, 100.0, 0.0, 0.0)))
    .gap(Is(20.0))
    .lines_up(Is(Some(Start)))
    .on_key(fn(k) {
      if k.code == @ui.key_escape {
        x.escapes.val += 1
        true
      } else {
        false
      }
    })
    |> ignore
    root.box(fn(around) {
      around.width(Is(Some(300.0))) |> ignore
      let f = input_node(around, x.field, placeholder="写点什么", submitted=fn(_) { x.sent.val += 1 })
      x.frame.val = f.parent()
      offers_node(
        around,
        f.parent().unwrap(),
        fn() { x.open.get() },
        fn() { keys },
        x.current,
        fn(r, k, _) { words_node(r, fn() { name_of(k) }, fn() { offers_head_words }) |> ignore },
        name_of,
        fn(i) {
          x.taken.push(i)
          x.open.set(false)
        },
        fn() {
          x.closes.val += 1
          x.open.set(false)
        },
        "可以选的",
        head=fn() { ("可以选的", "x") },
      )
    })
    |> ignore
    root.box(fn(u) {
      u
      .width(Is(Some(120.0)))
      .height(Is(Some(36.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .on_press(fn() { x.under.val += 1 })
      .says(Is(Some(@view.said(Button, label="下面"))))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (the field given the focus, then what it offers opened)
  t.click(TextField)
  x.open.set(true)
  t.draw()
  t.run_for(@ui.move_most_ms)
  x
}

///|
/// Where node `v` is drawn in the window.
fn offers_rect(v : @view.View?) -> (Double, Double, Double, Double) {
  match v {
    Some(v) => v.placed_window_now()
    None => (-1.0, -1.0, -1.0, -1.0)
  }
}

///|
/// Whether the field has the focus.
fn offers_in_field(t : @ui.Tester) -> Bool {
  match t.focused() {
    Some(s) => s.role == TextField
    None => false
  }
}

///|
test "offers: under its field, 6 off, lined up with its start, as wide as it; its head and rows read out; the focus left in the field" {
  let x = offers_tester()
  let (fx, fy, fw, fh) = offers_rect(x.frame.val)
  let d = x.t.get(Dialog, label="可以选的")
  let (dx, dy, dw, _) = d.rect
  assert_eq((dx, dy, dw), (fx, fy + fh + 6.0, fw))
  assert_true(x.t.find("可以选的") is Some(_))
  assert_true(x.t.find("x") is Some(_))
  x.t.get(Button, label="甲", selected=true) |> ignore
  x.t.get(Button, label="乙", selected=false) |> ignore
  assert_true(offers_in_field(x.t))
  // (what is typed the field's, a space and a letter alike)
  x.t.type_text("a b")
  assert_eq(x.field.text(), "a b")
  assert_true(x.open.get())
}

///|
test "offers: ↓ and ↑ choose round, Enter takes the one chosen, the focus in the field; closed, Enter is the field's" {
  let x = offers_tester()
  x.t.key(@ui.key_code_down)
  assert_eq(x.current.get(), 1)
  x.t.key(@ui.key_code_up)
  x.t.key(@ui.key_code_up)
  assert_eq(x.current.get(), 2)
  x.t.get(Button, label="丙", selected=true) |> ignore
  x.t.key(@ui.key_code_enter)
  assert_eq((x.taken, x.sent.val), ([2], 0))
  assert_true(offers_in_field(x.t))
  // (closed: Enter the field's, ↓ nothing of its)
  x.t.key(@ui.key_code_enter)
  x.t.key(@ui.key_code_down)
  assert_eq((x.taken, x.sent.val, x.current.get()), ([2], 1, 2))
}

///|
test "offers: Tab takes the one chosen, the focus staying; closed, Tab moves the focus on" {
  let x = offers_tester()
  x.t.key(@ui.key_code_down)
  x.t.key(@ui.key_tab)
  assert_eq(x.taken, [1])
  assert_true(offers_in_field(x.t))
  x.t.run_for(@kit.pop_out_ms)
  x.t.key(@ui.key_tab)
  assert_eq(x.taken, [1])
  assert_true(x.t.focused().map(fn(s) { s.label }) == Some("下面"), msg="\{Repr(x.t.focused().map(fn(s) { s.label }))}")
}

///|
test "offers: the pointer moving onto a row chooses it; a press on one takes it" {
  let x = offers_tester()
  let (rx, ry, rw, rh) = x.t.get(Button, label="丙").rect
  x.t.move_to(rx + rw / 2.0, ry + rh / 2.0)
  assert_eq(x.current.get(), 2)
  x.t.tap(rx + rw / 2.0, ry + rh / 2.0)
  assert_eq(x.taken, [2])
  x.t.run_for(@kit.pop_out_ms)
  assert_true(x.t.find("可以选的") is None)
}

///|
test "offers: Escape closes it alone, the next Escape the window's; one taken, an Escape at once after it is the window's, a frame between or none" {
  let x = offers_tester()
  x.t.key(@ui.key_escape)
  assert_eq((x.closes.val, x.escapes.val), (1, 0))
  x.t.run_for(@kit.pop_out_ms)
  x.t.key(@ui.key_escape)
  assert_eq((x.closes.val, x.escapes.val), (1, 1))
  for frames in [false, true] {
    let y = offers_tester()
    y.t.key_told(@ui.key_code_enter, 0, y.t.time())
    if frames {
      y.t.frame()
    }
    y.t.key_told(@ui.key_escape, 0, y.t.time())
    y.t.draw()
    assert_eq((y.taken, y.closes.val, y.escapes.val, y.sent.val), ([0], 0, 1, 0), msg="\{frames}")
  }
}

///|
test "offers: a press outside it and its field closes it, the press what it lands on's; one on the field does not" {
  let x = offers_tester()
  let (fx, fy, fw, fh) = offers_rect(x.frame.val)
  x.t.tap(fx + fw / 2.0, fy + fh / 2.0)
  x.t.tap(fx + fw - 10.0, fy + fh / 2.0)
  assert_eq(x.closes.val, 0)
  assert_true(x.open.get())
  let (bx, by, bw, bh) = x.t.get(Button, label="下面").rect
  x.t.tap(bx + bw / 2.0, by + bh / 2.0)
  assert_eq((x.closes.val, x.under.val), (1, 1))
  x.t.run_for(@kit.pop_out_ms)
  assert_true(x.t.find("可以选的") is None)
}

///|
test "offers: many, past its most: ↑ from the first to the last, round, brings it into sight" {
  let x = offers_tester(n=20)
  let d = x.t.get(Dialog, label="可以选的")
  let (_, dy, _, dh) = d.rect
  assert_true(dh <= offers_most + 0.5, msg="\{dh}")
  x.t.key(@ui.key_code_up)
  x.t.run_for(@ui.move_most_ms)
  assert_eq(x.current.get(), 19)
  let (_, ry, _, rh) = x.t.get(Button, label="第19").rect
  assert_true(ry >= dy && ry + rh <= dy + dh + 0.5, msg="\{Repr((ry, rh, dy, dh))}")
}

///|
/// Whether the row of `name` is drawn on the hover's ground (a rectangle of that colour under its words).
fn offers_lit(x : OffersAt, name : String) -> Bool {
  let (wx, wy, ww, wh) = x.t.rect_of(name).unwrap()
  let hover = @ui.tree_theme().color(Hover)
  x.t
  .drawn_rects()
  .iter()
  .any(fn(r) { r.4 == hover && r.0 <= wx && r.1 <= wy && r.0 + r.2 >= wx + ww && r.1 + r.3 >= wy + wh })
}

///|
test "offers: the one chosen on the hover's ground, and only it, as ↓ and ↑ choose another" {
  let x = offers_tester()
  assert_eq((offers_lit(x, "甲"), offers_lit(x, "乙"), offers_lit(x, "丙")), (true, false, false))
  x.t.key(@ui.key_code_down)
  x.t.run_for(@ui.move_most_ms)
  assert_eq((offers_lit(x, "甲"), offers_lit(x, "乙"), offers_lit(x, "丙")), (false, true, false))
  x.t.key(@ui.key_code_up)
  x.t.key(@ui.key_code_up)
  x.t.run_for(@ui.move_most_ms)
  assert_eq((offers_lit(x, "甲"), offers_lit(x, "乙"), offers_lit(x, "丙")), (false, false, true))
}

///|
test "offers: a mouse's pointer over its ground (its head's words, its padding) is the arrow, over a row the hand (ground_node)" {
  let x = offers_tester()
  let (dx, dy, dw, dh) = x.t.get(Dialog, label="可以选的").rect
  let shape_on = fn(px : Double, py : Double) {
    x.t.move_to(px, py)
    x.t.run_for(@ui.move_most_ms)
    x.t.cursor()
  }
  let points = [(dx + 3.0, dy + dh / 2.0), (dx + dw / 2.0, dy + 3.0), (dx + dw / 2.0, dy + dh - 3.0), (dx + dw - 3.0, dy + dh / 2.0)]
  let grounds = points.map(fn(p) { shape_on(p.0, p.1) })
  assert_eq(grounds, points.map(fn(_) { Arrow }), msg="its ground at \{Repr(points)}, it \{Repr((dx, dy, dw, dh))}")
  let (rx, ry, rw, rh) = x.t.get(Button, label="乙", selected=false).rect
  assert_eq(shape_on(rx + rw / 2.0, ry + rh / 2.0), Hand, msg="a row")
}
