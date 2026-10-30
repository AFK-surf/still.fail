// A modal layer of the window's tree (View::modal): the topmost on takes all input; what it does not hold (the tree's
// own nodes, the old views drawn under it) takes none, from the moment it is said on, as soon as it is said off theirs
// again, whatever frames came between: presses, the wheel, keys, Tab, what is read out.

///|
/// What the page (an old view under the layers) was told: its button pressed, the wheel over its box, its key, and
/// what its button is read out as.
priv struct Under {
  taps : Ref[Int]
  wheels : Ref[Int]
  keys : Ref[Int]
}

///|
/// A window: a page (an old view filling it: a button at the top left 100 by 60, read out as "page button", a box
/// below keeping the wheel, an `x` key read), and two modal layers over it, A then B (each the whole window, a tree
/// button of its own at (200, 0), 100 by 60 for A, at (200, 100) for B), on while `a` and `b` hold.
fn modal_window(a : @signals.Signal[Bool], b : @signals.Signal[Bool], pressed : Array[String]) -> (Tester, Under) {
  let under = { taps: Ref(0), wheels: Ref(0), keys: Ref(0) }
  let t = Tester::new(fn(_c) {  }, platform=0, keyboard=true)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("page button")
      if c.clicked(id) {
        under.taps.val = under.taps.val + 1
      }
      let bt = c.box(w=Px(100.0), h=Px(60.0), id~, fn() {  })
      c.semantics(bt, Button, id~, label="page button")
      c.focusable(id)
      let wb = c.id("page wheel")
      capture(c, wb)
      if wheel(c, wb) != 0.0 {
        under.wheels.val = under.wheels.val + 1
      }
      c.box(w=Px(100.0), h=Px(100.0), id=wb, fn() {  }) |> ignore
      if c.key_pressed(key_of_char('x')) {
        under.keys.val = under.keys.val + 1
      }
    })
    .over(Is(true))
    |> ignore
    for layer in [("A", a, 0.0), ("B", b, 100.0)] {
      let (name, on, y) = layer
      root.box(fn(l) {
        l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore
        l.box(fn(bt) {
          bt
          .offset(Is((200.0, y)))
          .width(Is(Some(100.0)))
          .height(Is(Some(60.0)))
          .on_press(fn() { pressed.push(name) })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  t.draw()
  t.drawn_now()
  (t, under)
}

///|
/// A press at (x, y), as a host's finger, no frame drawn after it.
fn tapped_at(x : Double, y : Double) -> Unit {
  finger(0, x, y)
  finger(2, x, y)
}

///|
test "modal layers: the topmost takes the presses, the one under it and the page none; the top one off, the one under it at once" {
  let a = @signals.signal(true, same=fn(x, y) { x == y })
  let b = @signals.signal(true, same=fn(x, y) { x == y })
  let pressed : Array[String] = []
  let (t, under) = modal_window(a, b, pressed)
  tapped_at(250.0, 30.0)
  tapped_at(250.0, 130.0)
  tapped_at(50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq((pressed.copy(), under.taps.val), (["B"], 0))
  // B off, no frame between: A's at once, still not the page's
  b.set(false)
  tapped_at(250.0, 30.0)
  tapped_at(50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq((pressed.copy(), under.taps.val), (["B", "A"], 0))
  // A off: the page's
  a.set(false)
  tapped_at(50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(under.taps.val, 1)
}

///|
/// The page under a layer said on (or off) between frames, a frame drawn before its input or not: what the page took
/// of a wheel over its box, its key, Tab (whether its button got the focus), and whether its button is read out.
fn under_a_layer(on : Bool, frame_first : Bool) -> (Int, Int, Bool, Bool) {
  let a = @signals.signal(!on, same=fn(x, y) { x == y })
  let b = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, under) = modal_window(a, b, [])
  a.set(on)
  if frame_first {
    t.frame_at(t.time() + frame_period_default)
  }
  finger_wheel(50.0, 100.0, 0.0, 10.0, 0)
  on_key(key_of_char('x'), 0)
  on_key(key_tab, 0)
  t.frame_at(t.time() + frame_period_default)
  let focused = match t.focused() {
    Some(s) => s.label == "page button"
    None => false
  }
  let read_out = t.semantics().iter().any(fn(s) { s.label == "page button" && !s.hidden })
  (under.wheels.val, under.keys.val, focused, read_out)
}

///|
test "a modal layer said on between frames: the page under it takes no wheel, no key, no Tab, and is read out none, whether a frame came first or not; said off, all of it again" {
  for frame_first in [false, true] {
    assert_eq(under_a_layer(true, frame_first), (0, 0, false, false), msg="on, a frame first: \{frame_first}")
    assert_eq(under_a_layer(false, frame_first), (1, 1, true, true), msg="off, a frame first: \{frame_first}")
  }
}

///|
/// A modal layer of the window's tree's, the whole window, a button of its own at (200, y), 100 by 60, pressed as
/// `name`.
fn modal_layer(l : @view.View, name : String, y : Double, pressed : Array[String]) -> Unit {
  l.over(Is(true)).modal(Is(true)) |> ignore
  l.box(fn(bt) {
    bt
    .offset(Is((200.0, y)))
    .width(Is(Some(100.0)))
    .height(Is(Some(60.0)))
    .on_press(fn() { pressed.push(name) })
    |> ignore
  })
  |> ignore
}

///|
test "modal layers drawn in another order, no frame between: the one drawn last now takes the presses" {
  let order = @signals.signal(["A", "B"], same=fn(x, y) { x == y })
  let pressed : Array[String] = []
  let t = Tester::new(fn(_c) {  }, platform=0)
  set_view_app(fn(root) {
    root.each(fn() { order.get() }, fn(k) { k }, fn(l, k) {
      let name = @signals.untracked(fn() { k.get() })
      modal_layer(l, name, if name == "A" { 0.0 } else { 100.0 }, pressed)
    })
  })
  t.draw()
  tapped_at(250.0, 30.0)
  tapped_at(250.0, 130.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(pressed.copy(), ["B"])
  // A drawn after B from now: A's, B's none
  order.set(["B", "A"])
  tapped_at(250.0, 30.0)
  tapped_at(250.0, 130.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(pressed.copy(), ["B", "A"])
}

///|
test "a modal layer made in a branch drawn under the topmost, no frame between: the topmost keeps the presses, a finger held on it too" {
  let c_on = @signals.signal(false, same=fn(x, y) { x == y })
  let pressed : Array[String] = []
  let t = Tester::new(fn(_c) {  }, platform=0)
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.over(Is(true)) |> ignore
      p.show(fn() { c_on.get() }, fn(l) { modal_layer(l, "C", 200.0, pressed) })
    })
    |> ignore
    root.box(fn(l) { modal_layer(l, "B", 100.0, pressed) }) |> ignore
  })
  t.draw()
  // held on B's button as C is made under it: B's when let go
  finger(0, 250.0, 130.0)
  c_on.set(true)
  finger(2, 250.0, 130.0)
  // B's again, C's none (under B)
  tapped_at(250.0, 130.0)
  tapped_at(250.0, 230.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(pressed.copy(), ["B", "B"])
}

///|
test "a modal layer made where one let go was, no frame between: the topmost as it is drawn now, not where the one let go was" {
  let x_on = @signals.signal(true, same=fn(x, y) { x == y })
  let y_on = @signals.signal(false, same=fn(x, y) { x == y })
  let pressed : Array[String] = []
  let (x_id, y_id) : (Ref[@view.NodeId?], Ref[@view.NodeId?]) = (Ref(None), Ref(None))
  let t = Tester::new(fn(_c) {  }, platform=0)
  set_view_app(fn(root) {
    // (a node drawn under B, let go: its index free)
    root.box(fn(p) {
      p.over(Is(true)) |> ignore
      p.show(fn() { x_on.get() }, fn(x) { x_id.val = Some(x.id()) })
    })
    |> ignore
    root.box(fn(l) { modal_layer(l, "B", 100.0, pressed) }) |> ignore
    // (Y, the whole window, drawn after B)
    root.show(fn() { y_on.get() }, fn(y) {
      y_id.val = Some(y.id())
      y.over(Is(true)).modal(Is(true)).on_press(fn() { pressed.push("Y") }) |> ignore
    })
  })
  t.draw()
  x_on.set(false)
  y_on.set(true)
  // (made in the index the one let go had)
  assert_eq(y_id.val.map(fn(i) { i.at }), x_id.val.map(fn(i) { i.at }))
  tapped_at(250.0, 130.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(pressed.copy(), ["Y"])
}

///|
test "a press held on the page as a modal layer comes over it, no frame between: called off then, nothing pressed as it is let go" {
  let a = @signals.signal(false, same=fn(x, y) { x == y })
  let b = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, under) = modal_window(a, b, [])
  finger(0, 50.0, 30.0)
  assert_true(g().down)
  a.set(true)
  assert_eq((g().down, g().active), (false, 0))
  finger(2, 50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(under.taps.val, 0)
  // A off: the page's again
  a.set(false)
  tapped_at(50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(under.taps.val, 1)
}

///|
/// A window of two old views, each a list of three rows (a button each, read out as "<name> row <k>", taking the
/// focus): `under` the whole window, and `top`'s in a modal layer over it, on while `on` holds.
fn listed_window(on : @signals.Signal[Bool]) -> Tester {
  let t = Tester::new(fn(_c) {  }, platform=0, keyboard=true)
  let rows = fn(name : String) {
    fn(c : Ctx) {
      c.list(
        "\{name} list",
        3,
        50.0,
        fn(k) {
          let id = c.id("\{name} row \{k}")
          let b = c.box(w=Fill(1.0), h=Px(50.0), id~, fn() {  })
          c.semantics(b, Button, id~, label="\{name} row \{k}")
          c.focusable(id)
        },
      )
      |> ignore
    }
  }
  set_view_app(fn(root) {
    old(root, rows("under")).over(Is(true)) |> ignore
    root.box(fn(l) {
      l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore
      old(l, rows("top")).over(Is(true)) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  t
}

///|
/// What Tab gives the focus to, `n` times, and the rows read out.
fn tabbed_and_read(t : Tester, n : Int) -> (Array[String], Array[String]) {
  let tabbed : Array[String] = []
  for _ in 0..<n {
    on_key(key_tab, 0)
    t.frame_at(t.time() + frame_period_default)
    match t.focused() {
      Some(s) => tabbed.push(s.label)
      None => tabbed.push("")
    }
  }
  let read = t.semantics().filter(fn(s) { s.label.contains(" row ") && !s.hidden }).map(fn(s) { s.label })
  read.sort()
  (tabbed, read)
}

///|
test "a list's rows in a page under a modal layer, built as the list is laid out: no Tab, read out none, built so under it or kept as they were; the layer's own all of it" {
  for on_first in [true, false] {
    let on = @signals.signal(on_first, same=fn(x, y) { x == y })
    let t = listed_window(on)
    // (built before it was on: kept as they were)
    on.set(true)
    t.frame_at(t.time() + frame_period_default)
    let (tabbed, read) = tabbed_and_read(t, 4)
    assert_eq(tabbed, ["top row 0", "top row 1", "top row 2", "top row 0"], msg="on at first: \{on_first}")
    assert_eq(read, ["top row 0", "top row 1", "top row 2"], msg="on at first: \{on_first}")
  }
}

///|
/// A window: a page (an old view filling it: a key catcher given the focus as it is first built, a list of 30 rows of
/// 50 on its left, 150 wide), and a modal layer over it (on while `on` holds) holding an old view 150 wide at x 200
/// with a list of its own; the lists' ids.
fn keyed_window(on : @signals.Signal[Bool]) -> (Tester, Ref[Int], Ref[Int]) {
  let (under_list, top_list) = (Ref(0), Ref(0))
  let first = Ref(true)
  let t = Tester::new(fn(_c) {  }, platform=0, keyboard=true)
  // (the list's id, as its state is kept by)
  let rows = fn(c : Ctx, key : String) {
    c.list(key, 30, 50.0, w=Px(150.0), fn(_k) { c.box(w=Fill(1.0), h=Px(50.0), fn() {  }) |> ignore }) |> ignore
    c.id(key)
  }
  set_view_app(fn(root) {
    old(root, fn(c) {
      ignore(c.key_catcher("catcher"))
      if first.val {
        first.val = false
        c.catch_keys("catcher", true)
      }
      under_list.val = rows(c, "under list")
    })
    .over(Is(true))
    |> ignore
    root.box(fn(l) {
      l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore
      // (laid out at x 200, 150 wide)
      l.row(Is(true)) |> ignore
      l.box(fn(s) { s.width(Is(Some(200.0))) |> ignore }) |> ignore
      old(l, fn(c) { top_list.val = rows(c, "top list") }).width(Is(Some(150.0))) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, under_list, top_list)
}

///|
test "keys under a modal layer: a key catcher of the page's under it gets no keys nor words, nor does its list scroll by PageDown or an arrow; the layer's list does" {
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, under_list, top_list) = keyed_window(on)
  let offset = fn(id : Ref[Int]) {
    match g().lists.get(id.val) {
      Some(st) => st.offset()
      None => -1.0
    }
  }
  // (the pointer over the page's list as the layer comes, no frame between: a finger lifted is nowhere once one is
  // drawn)
  finger(1, 75.0, 100.0)
  on.set(true)
  // the catcher (the focus), between frames
  on_key(key_of_char('q'), 0)
  on_text(0, "hi", 0, 0)
  assert_true(g().dev.catchers.values().all(fn(st) { st.came.is_empty() }))
  // over the page's list
  assert_eq((g().px, g().py), (75.0, 100.0))
  on_key(key_page_down, 0)
  on_key(key_down, 0)
  t.draw()
  assert_eq(offset(under_list), 0.0)
  // over the layer's
  finger(1, 275.0, 100.0)
  on_key(key_page_down, 0)
  t.draw()
  assert_true(offset(top_list) > 0.0)
}

///|
test "a page let go and made again under a modal layer, no frame between: what its field had the focus of takes no words" {
  let which = @signals.signal(1, same=fn(x, y) { x == y })
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let field = Field::new()
  let t = Tester::new(fn(_c) {  }, platform=0, keyboard=true)
  set_view_app(fn(root) {
    root.pick(fn() { which.get() }, fn(v, _k) {
      v.over(Is(true)) |> ignore
      old(v, fn(c) { c.editor("field", field~, font_size=10.0) |> ignore }).over(Is(true)) |> ignore
    })
    root.box(fn(l) { l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore }) |> ignore
  })
  t.draw()
  t.tap(50.0, 10.0)
  t.type_text("a")
  assert_eq(field.text(), "a")
  which.set(2)
  on.set(true)
  on_text(0, "b", 0, 0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(field.text(), "a", msg="no words after it was let go")
}

///|
test "rows of modal layers, one more put before the topmost, no frame between: the topmost stays so, a finger held on it pressing it as it is let go" {
  let order = @signals.signal(["B"], same=fn(x, y) { x == y })
  let pressed : Array[String] = []
  let t = Tester::new(fn(_c) {  }, platform=0)
  set_view_app(fn(root) {
    root.each(fn() { order.get() }, fn(k) { k }, fn(l, k) {
      let name = @signals.untracked(fn() { k.get() })
      modal_layer(l, name, if name == "A" { 0.0 } else { 100.0 }, pressed)
    })
  })
  t.draw()
  // (A made as the rows are put in order: B the last of them all along)
  finger(0, 250.0, 130.0)
  order.set(["A", "B"])
  finger(2, 250.0, 130.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(pressed.copy(), ["B"])
}

///|
test "a scroll bar's thumb of the page held as a modal layer comes over it: let go then; the layer gone, the pointer moved, the list stays where it was" {
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.list("list", 200, 40.0, fn(_i) { c.box(w=Fill(1.0), h=Px(40.0), fn() {  }) |> ignore }) |> ignore
    })
    .over(Is(true))
    |> ignore
    root.box(fn(l) { l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore }) |> ignore
  })
  t.draw()
  t.move(296.0, 200.0)
  t.run_for(scrollbar_fade_ms)
  t.move(296.0, 10.0)
  t.press_at(296.0, 10.0)
  assert_true(g().bar_drag != 0)
  on.set(true)
  assert_eq(g().bar_drag, 0)
  on.set(false)
  t.release(296.0, 10.0)
  t.move(296.0, 103.0)
  t.run_for(scrollbar_fade_ms)
  assert_eq(t.list_offset(), 0.0)
}

///|
/// A page's swipe back from the left edge of a stack (an old view's: page 1 over 0) called off: `how` 0 by a modal layer
/// said on at 50 ms by the tree's timeline (View::at_moment), the host's next event at 100; 1 by the host at 50; 2 by
/// the host at 100. The moments (from the swipe's start) the stack was told its swipe was called off at.
fn back_called_off(how : Int) -> Array[Double] {
  let nav = Nav::new(0)
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let root_v : Ref[@view.View?] = Ref(None)
  let off_at : Array[Double] = []
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root_v.val = Some(root)
    old(root, fn(c) {
      c.nav(nav, fn(i) { c.text("title \{i}", wrap=false) |> ignore }, bg=0xFFFFFFFFL) |> ignore
      // (what the stack is told of its swipe: when it is called off, written down)
      match c.back_next {
        Some(f) =>
          c.back_next = Some(fn(kind, x, w, at, progress) {
            if kind == 3 {
              off_at.push(at)
            }
            f(kind, x, w, at, progress)
          })
        None => ()
      }
    })
    .over(Is(true))
    |> ignore
    root.box(fn(l) { l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore }) |> ignore
  })
  t.draw()
  nav.push(1)
  t.run_for(move_most_ms)
  let t0 = t.time()
  let at = fn(ms : Double, kind : Int, x : Double) {
    t.fake.time = t0 + ms
    finger(kind, x, 400.0)
  }
  match root_v.val {
    Some(root) if how == 0 => root.at_moment(t0 + 50.0, fn() { on.set(true) }) |> ignore
    _ => ()
  }
  at(0.0, 0, 5.0)
  at(16.0, 1, 40.0)
  at(32.0, 1, 80.0)
  match how {
    0 => at(100.0, 1, 80.0)
    1 => at(50.0, 3, 80.0)
    _ => at(100.0, 3, 80.0)
  }
  t.frame_at(t0 + 116.0)
  off_at.map(fn(a) { a - t0 })
}

///|
test "a swipe back of the page called off by a modal layer said on at a moment of the tree's own: called off at that moment, not at the host's next word" {
  assert_eq(back_called_off(1), [50.0])
  assert_eq(back_called_off(2), [100.0])
  assert_eq(back_called_off(0), [50.0])
}

///|
/// A window: a page (an old view filling it, its button at the top left 100 by 60), a modal layer shown over it as
/// `on` turns (an old view of its own filling it, nothing of its own there yet), and after it a page that is no modal
/// layer's (an old view, its button where the first's is); how many times each button was pressed.
fn shown_over(on : @signals.Signal[Bool]) -> (Tester, Array[Int]) {
  let taps = [0, 0]
  let t = Tester::new(fn(_c) {  }, platform=0)
  let page = fn(k : Int) {
    fn(c : Ctx) {
      let id = c.id("button \{k}")
      if c.clicked(id) {
        taps[k] = taps[k] + 1
      }
      c.box(w=Px(100.0), h=Px(60.0), id~, fn() {  }) |> ignore
    }
  }
  set_view_app(fn(root) {
    old(root, page(0)).over(Is(true)) |> ignore
    root.show(fn() { on.get() }, fn(l) {
      l.over(Is(true)).modal(Is(true)) |> ignore
      old(l, fn(c) { c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }).over(Is(true)) |> ignore
    })
    root.box(fn(n) { old(n.over(Is(true)), page(1)).over(Is(true)) |> ignore }) |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, taps)
}

///|
test "a modal layer shown over the pages between frames, its old view not built yet: a press where their buttons are presses neither, the one drawn after it no modal layer's as well" {
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, taps) = shown_over(on)
  on.set(true)
  tapped_at(50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(taps.copy(), [0, 0])
  // built and drawn: still neither
  tapped_at(50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(taps.copy(), [0, 0])
  // gone: the one drawn last's
  on.set(false)
  tapped_at(50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(taps.copy(), [0, 1])
}

///|
test "a modal layer made and said off at a moment of the tree's own, a finger held on the topmost meanwhile: committed whole, it calls nothing off" {
  let pressed : Array[String] = []
  let root_v : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, platform=0)
  set_view_app(fn(root) {
    root_v.val = Some(root)
    root.box(fn(l) { modal_layer(l, "B", 100.0, pressed) }) |> ignore
  })
  t.draw()
  let t0 = t.time()
  let root = root_v.val.unwrap()
  // (at 50: a modal layer over B made, then said off, as one change)
  root.at_moment(t0 + 50.0, fn() {
    let a = root.box(fn(l) { modal_layer(l, "A", 0.0, pressed) })
    a.modal(Is(false)) |> ignore
  })
  |> ignore
  finger(0, 250.0, 130.0)
  t.fake.time = t0 + 100.0
  finger(2, 250.0, 130.0)
  t.frame_at(t0 + 116.0)
  assert_eq(pressed.copy(), ["B"])
}

///|
test "words let go on a page's field, another page pressed before: the field where they are let go takes them, as with none pressed" {
  let fields = [Field::new(), Field::new()]
  let t = Tester::new(fn(_c) {  }, platform=0, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    for k in 0..<2 {
      old(root, fn(c) { c.editor("field", field=fields[k], font_size=10.0) |> ignore })
      .width(Is(Some(200.0)))
      |> ignore
    }
  })
  t.draw()
  t.tap(50.0, 10.0)
  // (what is found at a place outside any input: whatever the last one went to)
  assert_true(hit_in(g().hit_ids, g().hit_rects, 250.0, 10.0) != 0, msg="the second page's field found")
  words_let_go(250.0, 10.0, "hi")
  t.draw()
  assert_eq((fields[0].text(), fields[1].text()), ("", "hi"))
}

///|
test "words let go where a page with a field was moved to, no frame between: on its field there, a frame drawn first or not" {
  for frame_first in [false, true] {
    let dx = @signals.signal(0.0, same=fn(x, y) { x == y })
    let field = Field::new()
    let t = Tester::new(fn(_c) {  }, platform=0, w=400.0, h=200.0)
    set_view_app(fn(root) {
      old(root, fn(c) { c.editor("field", field~, font_size=10.0) |> ignore })
      .width(Is(Some(150.0)))
      .height(Is(Some(200.0)))
      .offset(By(fn() { (dx.get(), 0.0) }))
      |> ignore
    })
    t.draw()
    dx.set(200.0)
    if frame_first {
      t.frame_at(t.time() + frame_period_default)
    }
    words_let_go(250.0, 10.0, "hi")
    t.draw()
    assert_eq(field.text(), "hi", msg="a frame first: \{frame_first}")
  }
}

///|
test "held on a page's button through an empty page over it, the layer of the one over it said modal and off again before it is let go: called off as it is said on, not pressed" {
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let taps = Ref(0)
  let t = Tester::new(fn(_c) {  }, platform=0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("page button")
      if c.clicked(id) {
        taps.val = taps.val + 1
      }
      c.box(w=Px(100.0), h=Px(60.0), id~, fn() {  }) |> ignore
    })
    .over(Is(true))
    |> ignore
    // (an old view over it drawing nothing there: the press passed on to the page's button)
    root.box(fn(l) {
      l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore
      old(l, fn(c) { c.box(left=300.0, top=300.0, w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }).over(Is(true))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  finger(0, 50.0, 30.0)
  assert_true(g().down)
  // (each its own change)
  on.set(true)
  assert_eq((g().down, g().active), (false, 0))
  on.set(false)
  finger(2, 50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(taps.val, 0)
  // a press of its own after: the button's
  tapped_at(50.0, 30.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(taps.val, 1)
}

///|
/// The scroll bar's thumb drawn now (3 wide), how opaque.
fn thumb_alpha(t : Tester) -> Int64 {
  match t.drawn_rects().filter(fn(r) { r.2 == scroll_bar_size }) {
    [r, ..] => r.4 & 0xFFL
    [] => -1L
  }
}

///|
test "a scroll bar's thumb lit as the pointer comes over it, unlit as it leaves, whatever else is built: held and called off by a modal layer, let go, left; the pointer out of the window" {
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.list("list", 200, 40.0, fn(_i) { c.box(w=Fill(1.0), h=Px(40.0), fn() {  }) |> ignore }) |> ignore
    })
    .over(Is(true))
    |> ignore
    root.box(fn(l) { l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore }) |> ignore
  })
  // (each frame judged by what it draws alone)
  t.check_looks(false)
  t.draw()
  t.move(296.0, 200.0)
  t.run_for(scrollbar_fade_ms)
  let light = thumb_alpha(t)
  t.move(296.0, 10.0)
  assert_true(thumb_alpha(t) > light)
  // held, called off by a modal layer, let go (the tree's: no input of the old view's), left: unlit
  t.press_at(296.0, 10.0)
  on.set(true)
  on.set(false)
  t.release(296.0, 10.0)
  t.move(296.0, 103.0)
  assert_eq(thumb_alpha(t), light)
  // over it again, then the pointer out of the window
  t.move(296.0, 10.0)
  assert_true(thumb_alpha(t) > light)
  on_pointer(7, 0.0, 0.0, 0)
  t.drawn_now()
  assert_eq(thumb_alpha(t), light)
}

///|
/// A page (an old view filling it: words picked with the pointer at its top, a list of 200 rows below them), and an
/// old view over it drawing nothing there (a box at (300, 260)), in a layer that is modal while `on` holds; shown only
/// then, where `shown`.
fn picked_under(on : @signals.Signal[Bool], shown : Bool, platform? : Int = 0) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform~)
  let over = fn(l : @view.View) {
    l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore
    old(l, fn(c) { c.box(left=300.0, top=260.0, w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }).over(Is(true))
    |> ignore
  }
  set_view_app(fn(root) {
    old(root, fn(c) {
      // (with the pointer, words picked by a drag, no list dragged)
      if platform != 2 {
        c.mouse_drags_lists(false)
      }
      c.column(w=Fill(1.0), h=Fill(1.0), fn() {
        c.selectable(fn() { c.rich([plain("hello wide world")], size=15.0) |> ignore })
        c.list("list", 200, 40.0, fn(i) { c.box(w=Fill(1.0), h=Px(40.0), fn() { c.text("row \{i}") |> ignore }) |> ignore })
        |> ignore
      })
      |> ignore
    })
    .over(Is(true))
    |> ignore
    if shown {
      root.show(fn() { on.get() }, over)
    } else {
      root.box(over) |> ignore
    }
  })
  t.draw()
  t.drawn_now()
  t
}

///|
/// A drag from (x0, y0) to (x1, y1) in 6 steps an input's step apart from `t0` (its moments the events' own), a frame
/// after each where `frames`; the moment after it.
fn dragged_at(t : Tester, x0 : Double, y0 : Double, x1 : Double, y1 : Double, t0 : Double, frames : Bool) -> Double {
  for k in 0..=6 {
    let f = k.to_double() / 6.0
    t.fake.time = t0 + k.to_double() * input_step_ms
    finger(if k == 0 { 0 } else if k == 6 { 2 } else { 1 }, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)
    if frames {
      t.frame_at(t.fake.time)
    }
  }
  t0 + 7.0 * input_step_ms
}

///|
test "a page's list and words under an empty page in a modal layer said on between frames (built or not yet): a drag there scrolls nothing and picks nothing, frames between its events or none; said off, it does" {
  for shown in [false, true] {
    for frames in [false, true] {
      let msg = "shown as it is on: \{shown}, frames between: \{frames}"
      let on = @signals.signal(false, same=fn(x, y) { x == y })
      // (a finger drags the list)
      let t = picked_under(on, shown, platform=2)
      on.set(true)
      let next = dragged_at(t, 100.0, 250.0, 100.0, 100.0, t.time(), frames)
      t.frame_at(next)
      assert_eq(t.list_offset(), 0.0, msg~)
      on.set(false)
      // (a press of its own: its moment past the one before's double click)
      let next = dragged_at(t, 100.0, 250.0, 100.0, 100.0, next + double_click_ms, frames)
      t.frame_at(next)
      assert_true(t.list_offset() > 0.0, msg~)
      // (the pointer picks the words)
      let on = @signals.signal(false, same=fn(x, y) { x == y })
      let t = picked_under(on, shown)
      let (_, y, _, h) = t.rect_of("hello wide world").unwrap()
      let mid = y + h / 2.0
      on.set(true)
      let next = dragged_at(t, 1.0, mid, 200.0, mid, t.time(), frames)
      t.frame_at(next)
      assert_eq(t.ctx().selected_text(), "", msg~)
      on.set(false)
      let next = dragged_at(t, 1.0, mid, 200.0, mid, next + double_click_ms, frames)
      t.frame_at(next)
      assert_eq(t.ctx().selected_text(), "hello wide world", msg~)
    }
  }
}

///|
test "words being picked on a page through an empty page over it, its layer said modal and off again before the rest of the drag: picked as far as they were, no further" {
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let t = picked_under(on, false)
  let (_, y, _, h) = t.rect_of("hello wide world").unwrap()
  let mid = y + h / 2.0
  finger(0, 1.0, mid)
  t.drawn_now()
  finger(1, 60.0, mid)
  t.drawn_now()
  // (each its own change)
  on.set(true)
  assert_false(picked.dragging)
  t.drawn_now()
  let at_off = t.ctx().selected_text()
  on.set(false)
  finger(1, 200.0, mid)
  t.drawn_now()
  finger(2, 200.0, mid)
  t.drawn_now()
  assert_eq(t.ctx().selected_text(), at_off)
}

///|
/// A page (an old view filling it: a stack of two pages, 1 over 0) and an empty old view over it in a layer that is
/// modal while `on` holds; what its stack was told of a swipe back, by kind (0 begun, 1 moved, 3 called off, 4 done).
fn stacked_under(on : @signals.Signal[Bool], platform : Int) -> (Tester, Nav[Int], Array[Int]) {
  let nav = Nav::new(0)
  let told : Array[Int] = []
  let t = Tester::new(fn(_c) {  }, platform~)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.nav(nav, fn(i) { c.text("title \{i}", wrap=false) |> ignore }, bg=0xFFFFFFFFL) |> ignore
      match c.back_next {
        Some(f) =>
          c.back_next = Some(fn(kind, x, w, at, progress) {
            told.push(kind)
            f(kind, x, w, at, progress)
          })
        None => ()
      }
    })
    .over(Is(true))
    |> ignore
    root.box(fn(l) {
      l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore
      old(l, fn(c) { c.box(left=300.0, top=600.0, w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }).over(Is(true))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  nav.push(1)
  t.run_for(move_most_ms)
  (t, nav, told)
}

///|
test "a swipe back from the left edge of a page under a modal layer: none while it is on, no frame between; one begun as it comes called off then, the rest of it none's though it goes" {
  // (each event at a moment of its own, no frame between them)
  let at = fn(t : Tester, ms : Double, kind : Int, x : Double) {
    t.fake.time = ms
    finger(kind, x, 400.0)
  }
  // on before it: nothing begun
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, nav, told) = stacked_under(on, 0)
  let t0 = t.time()
  on.set(true)
  at(t, t0, 0, 5.0)
  at(t, t0 + 16.0, 1, 40.0)
  at(t, t0 + 32.0, 1, 200.0)
  at(t, t0 + 48.0, 2, 200.0)
  t.frame_at(t0 + 48.0 + move_most_ms)
  assert_eq((told.copy(), nav.depth()), ([], 2))
  // begun, then a modal layer on and off again: called off once, nothing more of it told
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, nav, told) = stacked_under(on, 0)
  let t0 = t.time()
  at(t, t0, 0, 5.0)
  at(t, t0 + 16.0, 1, 40.0)
  at(t, t0 + 32.0, 1, 80.0)
  let begun = told.length()
  on.set(true)
  on.set(false)
  at(t, t0 + 48.0, 1, 300.0)
  at(t, t0 + 64.0, 2, 300.0)
  t.frame_at(t0 + 64.0 + move_most_ms)
  assert_true(begun > 0 && told[0] == 0, msg="\{told}")
  assert_eq(told[begun:].to_array(), [3])
  assert_eq(nav.depth(), 2)
}

///|
test "the system's back over a page under a modal layer: none of its while it is on; one begun as it comes called off then, the rest of it none's; with none on, its" {
  // on before it: nothing
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, nav, told) = stacked_under(on, 2)
  on.set(true)
  on_back(0, 0.0, 0.0, 0)
  on_back(1, 100.0, 0.3, 0)
  on_back(2, 0.0, 1.0, 0)
  t.run_for(move_most_ms)
  assert_eq((told.copy(), nav.depth()), ([], 2))
  // begun, then a modal layer on and off again: called off once, the rest none's
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, nav, told) = stacked_under(on, 2)
  on_back(0, 0.0, 0.0, 0)
  on_back(1, 100.0, 0.3, 0)
  on.set(true)
  on.set(false)
  on_back(1, 200.0, 0.6, 0)
  on_back(2, 0.0, 1.0, 0)
  t.run_for(move_most_ms)
  assert_eq((told.copy(), nav.depth()), ([0, 1, 3], 2))
  // none on: back
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let (t, nav, _) = stacked_under(on, 2)
  on_back(0, 0.0, 0.0, 0)
  on_back(1, 100.0, 0.3, 0)
  on_back(2, 0.0, 1.0, 0)
  t.run_for(move_most_ms)
  assert_eq(nav.depth(), 1)
}

///|
test "the caret's handle of a field of a page under an empty page in a modal layer said on between frames: dragged, no frame between, the caret stays; said off, it goes with it" {
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let field = Field::new()
  field.set("hello world")
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=2)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("field", font_size=16.0, field~) |> ignore }).over(Is(true)) |> ignore
    root.box(fn(l) {
      l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore
      old(l, fn(c) { c.box(left=280.0, top=180.0, w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }).over(Is(true))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.tap(20.0, 10.0)
  t.draw()
  let st = g().editors.get(g().focus).unwrap()
  assert_true(st.handle_on)
  let before = field.selection()
  let hx = st.handle_x
  let hy = st.handle_y + handle_r * 1.4
  // (each event at a moment of its own, no frame between them)
  let drag = fn(t0 : Double) {
    for k in 0..=6 {
      t.fake.time = t0 + k.to_double() * input_step_ms
      finger(if k == 0 { 0 } else if k == 6 { 2 } else { 1 }, hx + 10.0 * k.to_double(), hy)
    }
  }
  on.set(true)
  let t0 = t.time()
  drag(t0)
  t.frame_at(t0 + 7.0 * input_step_ms)
  assert_eq(field.selection(), before)
  // (the field as it was: focused, its handle shown where it was)
  assert_true(st.handle_on && g().focus != 0, msg="handle \{st.handle_on} \{st.handle} focus \{g().focus} at \{st.handle_x},\{st.handle_y} was \{hx}")
  on.set(false)
  // (a press of its own: its moment past the one before's double click)
  let t1 = t0 + 7.0 * input_step_ms + double_click_ms
  drag(t1)
  t.frame_at(t1 + 7.0 * input_step_ms)
  assert_true(field.selection().0 > before.0, msg="\{field.selection()} handle \{st.handle_on} focus \{g().focus_allowed()}")
}

///|
/// The system's back begun over a page (A, an old view taking back) and gone on as what takes back changes: `release`,
/// A let go meanwhile; else B (another old view) taking back from then; a frame drawn between where `frame_between`.
/// What each was told of it ("<who> <kind>"), and whether each step was told at its own moment (as said with it).
fn back_switched(release : Bool, frame_between : Bool) -> (Array[String], Array[Bool]) {
  let who = @signals.signal("A", same=fn(x, y) { x == y })
  let a_on = @signals.signal(true, same=fn(x, y) { x == y })
  let told : Array[String] = []
  let told_at : Array[Double] = []
  let t = Tester::new(fn(_c) {  }, platform=2)
  // (taking back as Ctx::on_back does, each step told)
  let takes = fn(c : Ctx, name : String) {
    part_live()
    if who.get() == name {
      c.back_next = Some(fn(kind, _x, _w, at, _p) {
        told.push("\{name} \{kind}")
        told_at.push(at)
      })
      c.back_node_next = -1
      c.back_island_next = if c.layer_cur == 0 { island_building.val } else { None }
    }
  }
  set_view_app(fn(root) {
    root.show(fn() { a_on.get() }, fn(v) {
      v.over(Is(true)) |> ignore
      old(v, fn(c) { takes(c, "A") }).over(Is(true)) |> ignore
    })
    old(root, fn(c) { takes(c, "B") }).over(Is(true)) |> ignore
  })
  t.draw()
  let t0 = t.time()
  // (each step its own moment, said with it, taken later by the host)
  let back = fn(ms : Double, kind : Int, x : Double, p : Double) {
    t.fake.time = t0 + ms + 30.0
    t.fake.event_at = t0 + ms
    on_back(kind, x, p, 0)
    t.fake.event_at = -1.0
  }
  back(20.0, 0, 0.0, 0.0)
  back(36.0, 1, 100.0, 0.3)
  if release {
    a_on.set(false)
  } else {
    who.set("B")
  }
  if frame_between {
    t.frame_at(t0 + 70.0)
  }
  back(80.0, 1, 200.0, 0.6)
  back(96.0, 2, 0.0, 1.0)
  t.frame_at(t0 + 200.0)
  let said = [20.0, 36.0, 80.0, 96.0]
  (told, told_at.mapi(fn(i, a) { i < said.length() && a == t0 + said[i] }))
}

///|
test "the system's back held by what took it as it began: what takes back changing meanwhile is told none of it, a frame between or none; that one let go, it called off for it once; each step at its own moment" {
  for frame_between in [true, false] {
    let msg = "a frame between: \{frame_between}"
    let switched = back_switched(false, frame_between)
    assert_eq(switched, (["A 0", "A 1", "A 1", "A 4"], [true, true, true, true]), msg="\{msg}: \{switched}")
    assert_eq(back_switched(true, frame_between).0, ["A 0", "A 1", "A 3"], msg~)
  }
}

///|
/// A step of back as a test reads it.
fn step_said(s : BackStep) -> String {
  match s {
    Began(_, _) => "began"
    Moved(_, _) => "moved"
    LetGo(_, _) => "let go"
    CalledOff => "called off"
    Back => "back"
  }
}

///|
/// The system's back begun over a page (an old view following it: Ctx::follow_back), then at 50 ms, as an event of its
/// own, that page `how`: 0 let go, 1 set leaving, 2 said to take no press; then the gesture goes on. What it was told by
/// then, whether each was told at the moment of the event it came by, and what it was told after.
fn back_let_go_of(how : Int) -> (Array[String], Array[Bool], Array[String]) {
  let a_on = @signals.signal(true, same=fn(x, y) { x == y })
  let enabled = @signals.signal(true, same=fn(x, y) { x == y })
  let told : Array[String] = []
  let told_at : Array[Double] = []
  let t = Tester::new(fn(_c) {  }, platform=2)
  set_view_app(fn(root) {
    root.show(
      fn() { a_on.get() },
      fn(v) {
        v.over(Is(true)).presses(By(fn() { enabled.get() })) |> ignore
        old(v, fn(c) {
          part_live()
          c.follow_back(fn(s) {
            told.push(step_said(s))
            told_at.push(view_moment())
          })
        })
        .over(Is(true))
        |> ignore
      },
      leave=if how == 1 { move_most_ms } else { 0.0 },
    )
  })
  t.draw()
  let t0 = t.time()
  let back = fn(ms : Double, kind : Int, x : Double, p : Double) {
    t.fake.time = t0 + ms + 30.0
    t.fake.event_at = t0 + ms
    on_back(kind, x, p, 0)
    t.fake.event_at = -1.0
  }
  back(20.0, 0, 0.0, 0.0)
  back(36.0, 1, 100.0, 0.3)
  view_tree().unwrap().event(t0 + 50.0, fn() {
    if how == 2 {
      enabled.set(false)
    } else {
      a_on.set(false)
    }
  })
  let by_then = told.copy()
  let said = [20.0, 36.0, 50.0]
  let at_own = told_at.mapi(fn(i, a) { i < said.length() && a == t0 + said[i] })
  back(80.0, 1, 200.0, 0.6)
  back(96.0, 2, 0.0, 1.0)
  t.frame_at(t0 + 200.0)
  (by_then, at_own, told[by_then.length():].to_array())
}

///|
test "the system's back of a page let go, set leaving, or said to take no press as an event of its own, no frame or input after: called off for it then, at that event's moment, once; the rest of the gesture nobody's" {
  for how in [0, 1, 2] {
    assert_eq(back_let_go_of(how), (["began", "moved", "called off"], [true, true, true], []), msg="how: \{how}")
  }
}

///|
/// A page (an old view) under an empty one in a layer that is modal while `on` holds, taking back as it is built: in a
/// layer of its own opened over all of it (Ctx::overlay, a sheet's: `in_layer`), or as itself (Ctx::follow_back). What it
/// was told of the system's back, the layer on.
fn back_under_modal(in_layer : Bool) -> Array[String] {
  let on = @signals.signal(false, same=fn(x, y) { x == y })
  let told : Array[String] = []
  let t = Tester::new(fn(_c) {  }, platform=2)
  set_view_app(fn(root) {
    old(root, fn(c) {
      part_live()
      let follow = fn() { c.follow_back(fn(s) { told.push(step_said(s)) }) }
      if in_layer {
        c.overlay("sheet", fn() { follow() }) |> ignore
      } else {
        follow()
      }
    })
    .over(Is(true))
    |> ignore
    root.box(fn(l) {
      l.over(Is(true)).modal(By(fn() { on.get() })) |> ignore
      old(l, fn(c) { c.box(left=300.0, top=600.0, w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore }).over(Is(true))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  on.set(true)
  t.draw()
  on_back(0, 0.0, 0.0, 0)
  on_back(1, 100.0, 0.3, 0)
  on_back(2, 0.0, 1.0, 0)
  told
}

///|
test "the system's back under a modal layer: what a page under it takes back by as itself none of it; what it opened over all of it (a layer of its own) all of it" {
  assert_eq(back_under_modal(false), [])
  assert_eq(back_under_modal(true), ["began", "moved", "back"])
}

///|
/// A window whose one old view follows the system's back (Ctx::follow_back), each step told "<name> <step>" with the
/// moment of the event it came by.
fn following(name : String, told : Array[(String, Double)]) -> (@view.View) -> Unit {
  fn(root) {
    old(root, fn(c) {
      part_live()
      c.follow_back(fn(s) { told.push(("\{name} \{step_said(s)}", view_moment())) })
    })
    .over(Is(true))
    |> ignore
  }
}

///|
test "the system's back of an old view going on as the window's tree is made anew (another view in the same place) or the window leaves the front: called off for it then, at that moment, once; the rest of it nobody's; a back begun after, the one there then" {
  for how in ["tree", "front"] {
    let told : Array[(String, Double)] = []
    let t = Tester::new(fn(_c) {  }, platform=2)
    set_view_app(following("A", told))
    t.draw()
    let t0 = t.time()
    let back = fn(ms : Double, kind : Int, x : Double, p : Double) {
      t.fake.time = t0 + ms + 30.0
      t.fake.event_at = t0 + ms
      on_back(kind, x, p, 0)
      t.fake.event_at = -1.0
    }
    back(20.0, 0, 0.0, 0.0)
    back(36.0, 1, 100.0, 0.3)
    // (at 50, as an event of its own)
    t.fake.event_at = t0 + 50.0
    if how == "tree" {
      set_view_app(following("B", told))
    } else {
      on_app_state(1)
    }
    t.fake.event_at = -1.0
    assert_eq(told.copy(), [("A began", t0 + 20.0), ("A moved", t0 + 36.0), ("A called off", t0 + 50.0)], msg=how)
    if how == "front" {
      on_app_state(3)
    }
    t.frame_at(t0 + 60.0)
    back(80.0, 1, 200.0, 0.6)
    back(96.0, 2, 0.0, 1.0)
    assert_eq(told.length(), 3, msg="\{how}: \{told}")
    // a back of its own after: the one there now
    back(120.0, 0, 0.0, 0.0)
    back(136.0, 2, 0.0, 1.0)
    let now = if how == "tree" { "B" } else { "A" }
    assert_eq(told[3:].to_array().map(fn(e) { e.0 }), ["\{now} began", "\{now} back"], msg=how)
  }
}

///|
/// An old view the whole window whose builds read where a tap landed anywhere (Ctx::tapped_anywhere), counted, a button
/// at the top left (100 by 60).
fn tapping(taps : Ref[Int]) -> (@view.View) -> Unit {
  fn(root) {
    old(root, fn(c) {
      if c.tapped_anywhere() is Some(_) {
        taps.val = taps.val + 1
      }
      c.box(w=Px(100.0), h=Px(60.0), id=c.id("button"), fn() {  }) |> ignore
    })
    .over(Is(true))
    |> ignore
  }
}

///|
test "the pointer held on an old view as the window's tree is made anew: what is left of the press nobody's, a frame between or none, no tap of it; a press after, the new one's" {
  for frame_between in [false, true] {
    let msg = "a frame between: \{frame_between}"
    let (a_taps, b_taps) = (Ref(0), Ref(0))
    let t = Tester::new(fn(_c) {  }, platform=0)
    set_view_app(tapping(a_taps))
    t.draw()
    let t0 = t.time()
    t.fake.time = t0 + 10.0
    finger(0, 50.0, 30.0)
    // (at 20, as an event of its own)
    t.fake.event_at = t0 + 20.0
    set_view_app(tapping(b_taps))
    t.fake.event_at = -1.0
    if frame_between {
      t.frame_at(t0 + 30.0)
    }
    t.fake.time = t0 + 40.0
    finger(2, 50.0, 30.0)
    t.frame_at(t0 + 50.0)
    assert_eq((a_taps.val, b_taps.val), (0, 0), msg~)
    // a press of its own after: the new one's
    t.fake.time = t0 + 50.0 + double_click_ms
    tapped_at(50.0, 30.0)
    t.frame_at(t.fake.time + frame_period_default)
    assert_eq(b_taps.val, 1, msg~)
  }
}
