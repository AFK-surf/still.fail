// An old view hosted in a node of the window's tree drawn bigger or smaller (View::scale, its own or what holds it):
// drawn, cut, pressed, typed into, selected in and read out where it is drawn, as big, as what the tree draws is (one
// projection); laid out as big as its node.

///|
/// A holder 200 by 100 drawn `s` as big about its top left, holding an old view all of it: an editor of `field` 200 by
/// 20 at its top; under it a button 100 by 50 at its right (read out "old button", its clicks counted as "button"); and
/// one 60 by 30 at its right edge, running 20 past it (cut there), its clicks counted as "over". The button drawn
/// `hosted_lit` while the mouse's pointer is on it (Ctx::hovered). `nested`: the holder
/// at (40, 40) inside a node at the window's top left that is drawn `s` as big about its top left (the holder itself
/// whole); else the holder at (20, 20), drawn `s` as big itself.
fn hosted_scaled(s : @signals.Signal[Double], pressed : Map[String, Int], field : Field, nested? : Bool = false, platform? : Int = 0) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform~)
  let count = fn(k : String) { pressed[k] = pressed.get(k).unwrap_or(0) + 1 }
  let holder = fn(h : @view.View) {
    old(h, fn(c) {
      let button = c.id("old button")
      if c.clicked(button) {
        count("button")
      }
      let over = c.id("over")
      if c.clicked(over) {
        count("over")
      }
      c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("e", field~, font_size=10.0) |> ignore }) |> ignore
      c.box(dir=Row, w=Px(200.0), h=Px(50.0), fn() {
        c.box(w=Px(100.0), h=Px(50.0), fn() {  }) |> ignore
        let b = c.box(w=Px(100.0), h=Px(50.0), bg=if c.hovered(button) { hosted_lit } else { 0x3366CCFFL }, id=button, fn() {  })
        c.semantics(b, Button, id=button, label="old button")
      })
      |> ignore
      c.box(w=Px(200.0), h=Px(30.0), fn() {
        c.layer(fn() { c.box(w=Px(60.0), h=Px(30.0), tx=160.0, bg=0xCC3333FFL, id=over, fn() {  }) |> ignore }) |> ignore
      })
      |> ignore
    }).grow(Is(1.0))
    |> ignore
  }
  set_view_app(fn(root) {
    if nested {
      root.box(fn(o) {
        o.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(200.0))).scale(By(fn() { s.get() }), about=At(0.0, 0.0)) |> ignore
        o.box(fn(h) {
          h.over(Is(true)).offset(Is((40.0, 40.0))).width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
          holder(h)
        })
        |> ignore
      })
      |> ignore
    } else {
      root.box(fn(h) {
        h
        .over(Is(true))
        .offset(Is((20.0, 20.0)))
        .width(Is(Some(200.0)))
        .height(Is(Some(100.0)))
        .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
        |> ignore
        holder(h)
      })
      |> ignore
    }
  })
  t.draw()
  t
}

///|
/// The hosted button's ground while the mouse's pointer is on it.
let hosted_lit : Int64 = 0x66AA33FFL

///|
/// How many times `k` was pressed.
fn hosted_pressed(pressed : Map[String, Int], k : String) -> Int {
  pressed.get(k).unwrap_or(0)
}

///|
test "an old view hosted in a node drawn half as big: read out and pressed where it is drawn, as big; nothing where it is laid out but not drawn; back to whole, where it is laid out again" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let t = hosted_scaled(s, pressed, Field::new())
  // (the button laid out at (120, 40) 100 by 50, drawn at (70, 30) 50 by 25)
  let blue = fn() {
    t.drawn_rects().filter(fn(r) { r.4 == 0x3366CCFFL }).map(fn(r) { (r.0, r.1, r.2, r.3) })
  }
  assert_eq(blue(), [(70.0, 30.0, 50.0, 25.0)], msg="drawn there, as big")
  assert_eq(t.get(Button, label="old button").rect, (70.0, 30.0, 50.0, 25.0), msg="read out where it is drawn")
  t.tap(80.0, 40.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "button"), 1, msg="pressed where it is drawn")
  t.tap(150.0, 60.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "button"), 1, msg="where it is laid out but not drawn: nothing")
  // (whole again: where it is laid out)
  s.set(1.0)
  t.draw()
  assert_eq(t.get(Button, label="old button").rect, (120.0, 40.0, 100.0, 50.0), msg="whole: read out where it is laid out")
  t.tap(150.0, 60.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "button"), 2, msg="whole: pressed where it is laid out")
}

///|
test "an old view hosted in a node whole inside one drawn half as big (what holds it scaled, it offset in it): read out and pressed where it is drawn, as big" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let t = hosted_scaled(s, pressed, Field::new(), nested=true)
  // (the holder at (40, 40) in what is drawn half as big at the window's top left: drawn at (20, 20); the button laid
  // out at (100, 20) in it: drawn at (70, 30) 50 by 25)
  assert_eq(t.get(Button, label="old button").rect, (70.0, 30.0, 50.0, 25.0), msg="read out where it is drawn")
  t.tap(80.0, 40.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "button"), 1, msg="pressed where it is drawn")
}

///|
test "an old view hosted in a node drawn half as big: what runs past it cut where it is drawn, pressed only where it shows" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let t = hosted_scaled(s, pressed, Field::new())
  // (the one at its right edge laid out at (180, 90) 60 by 30, 20 past the holder's 220: drawn at (100, 55) 30 by 15,
  // cut at the holder's drawn right edge, 120: 100 to 120 shows, 120 to 130 is cut)
  t.tap(115.0, 60.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "over"), 1, msg="where it shows: pressed")
  t.tap(125.0, 60.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "over"), 1, msg="past where it is cut: nothing")
}

///|
test "an old view hosted in a node drawn half as big, a press held on its button as the node is drawn as nothing, then moved off and let go: nothing pressed, nothing divided by its scale; whole again, pressed where it is laid out" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let t = hosted_scaled(s, pressed, Field::new())
  t.touch(0, 80.0, 40.0)
  t.draw()
  s.set(0.0)
  t.draw()
  t.touch(1, 200.0, 150.0)
  t.touch(2, 200.0, 150.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "button"), 0, msg="drawn as nothing, the held press moved off and let go: nothing pressed")
  // (drawn as nothing, a whole press where the button was drawn, and where it is laid out: neither taken)
  t.tap(80.0, 40.0)
  t.draw()
  t.tap(150.0, 60.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "button"), 0, msg="drawn as nothing: nothing pressed where it was drawn or laid out")
  s.set(1.0)
  t.draw()
  t.tap(150.0, 60.0)
  t.draw()
  assert_eq(hosted_pressed(pressed, "button"), 1, msg="whole again: pressed where it is laid out")
}

///|
/// The hosted editor tapped `local` points along its line (in its own terms) where it is drawn at scale `scale`: the
/// caret it puts down, and where the host is told the caret is.
fn hosted_caret(scale : Double, local : Double) -> (Int, (Double, Double, Double, Double)) {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let field = Field::new(text="abcdefghij")
  let t = hosted_scaled(s, {}, field)
  // (the editor laid out at (20, 20) 200 by 20, drawn at (20, 20) 200 s by 20 s)
  t.tap(20.0 + local * scale, 20.0 + 10.0 * scale)
  t.draw()
  t.draw()
  (field.selection().1, t.ime_rect())
}

///|
test "an editor in an old view hosted in a node drawn half as big: a tap where it is drawn puts its caret down where it does whole; the host told the caret where it is drawn, as big" {
  let (whole, whole_rect) = hosted_caret(1.0, 33.0)
  let (half, half_rect) = hosted_caret(0.5, 33.0)
  assert_true(whole > 0, msg="whole: its caret put down in its words: \{whole}")
  assert_eq(half, whole, msg="half: the caret where a tap puts it whole")
  let (x, y, w, h) = whole_rect
  assert_eq(
    half_rect,
    (20.0 + (x - 20.0) * 0.5, 20.0 + (y - 20.0) * 0.5, w * 0.5, h * 0.5),
    msg="half: the host told the caret where it is drawn, as big: \{whole_rect} whole",
  )
}

///|
test "an editor focused in an old view hosted in a node, its caret at its start: drawn whole, half as big, whole again, the host told where its caret is each time, as big (its corner the same, its size not)" {
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let field = Field::new(text="abcdefghij")
  let t = hosted_scaled(s, {}, field)
  t.tap(20.0 + 1.0, 30.0)
  t.draw()
  field.set(field.text(), caret=0)
  t.draw()
  let (x, y, w, h) = t.ime_rect()
  s.set(0.5)
  t.draw()
  assert_eq(t.ime_rect(), (20.0 + (x - 20.0) * 0.5, 20.0 + (y - 20.0) * 0.5, w * 0.5, h * 0.5), msg="half: told again")
  s.set(1.0)
  t.draw()
  assert_eq(t.ime_rect(), (x, y, w, h), msg="whole again: told again")
  // (a little bigger: its corner on the same whole pixel, only its size other; told again so)
  s.set(1.04)
  t.draw()
  let (bx, by) = (20.0 + (x - 20.0) * 1.04, 20.0 + (y - 20.0) * 1.04)
  assert_eq((bx.to_int(), by.to_int()), (x.to_int(), y.to_int()), msg="a little bigger: its corner on the same pixel")
  assert_eq(t.ime_rect(), (bx, by, w * 1.04, h * 1.04), msg="a little bigger, its corner where it was: told again, as big")
}

///|
/// The hosted editor's words picked by a pointer dragged from `from` to `to` points along its line (its own terms)
/// where it is drawn at scale `scale`: what is picked.
fn hosted_picked(scale : Double, from : Double, to : Double) -> (Int, Int) {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let field = Field::new(text="abcdefghij")
  let t = hosted_scaled(s, {}, field)
  t.host_says_finger(Some(false))
  let y = 20.0 + 10.0 * scale
  t.drag(20.0 + from * scale, y, 20.0 + to * scale, y)
  t.draw()
  field.selection()
}

///|
test "an editor in an old view hosted in a node drawn half as big: words picked by a pointer dragged across where they are drawn, as dragged across them whole" {
  let whole = hosted_picked(1.0, 7.0, 40.0)
  let half = hosted_picked(0.5, 7.0, 40.0)
  assert_true(whole.0 != whole.1, msg="whole: words picked: \{whole}")
  assert_eq(half, whole, msg="half: the same words picked")
}

///|
test "an old view hosted in a node laid out off the window's corner, drawn moved and half as big, then moved again: read out, pressed, its caret put down and told where it is drawn each time" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let moved = @signals.signal((20.0, 10.0), same=fn(a, b) { a == b })
  let clicks = Ref(0)
  let field = Field::new(text="abcdefghij")
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    // (laid out 30 in and 10 down by its holder's padding: its place as laid out not the window's corner)
    root.padding(Is((30.0, 10.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .offset(By(fn() { moved.get() }))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        let b = c.id("old button")
        if c.clicked(b) {
          clicks.val += 1
        }
        c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("e", field~, font_size=10.0) |> ignore }) |> ignore
        c.box(dir=Row, w=Px(200.0), h=Px(50.0), fn() {
          c.box(w=Px(100.0), h=Px(50.0), fn() {  }) |> ignore
          let n = c.box(w=Px(100.0), h=Px(50.0), bg=0x3366CCFFL, id=b, fn() {  })
          c.semantics(n, Button, id=b, label="old button")
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  for step in [(20.0, 10.0), (60.0, 40.0)] {
    moved.set(step)
    t.draw()
    // (laid out at (30, 10), drawn from (30 + dx, 10 + dy) half as big: the button laid out 100 in and 20 down in it)
    let (qx, qy) = (30.0 + step.0, 10.0 + step.1)
    assert_eq(t.get(Button, label="old button").rect, (qx + 50.0, qy + 10.0, 50.0, 25.0), msg="moved \{step}: read out where it is drawn")
    let before = clicks.val
    t.tap(qx + 60.0, qy + 20.0)
    t.draw()
    assert_eq(clicks.val, before + 1, msg="moved \{step}: pressed where it is drawn")
    // (its caret put down a tap 33 along its line, where it is drawn: as whole)
    t.tap(qx + 33.0 * 0.5, qy + 5.0)
    t.draw()
    let caret = field.selection().1
    assert_true(caret > 0, msg="moved \{step}: its caret put down in its words: \{caret}")
    let (x, y, w, h) = t.ime_rect()
    assert_true(x >= qx && x <= qx + 100.0 && y >= qy && y <= qy + 10.0 && h <= 10.0 + 0.001, msg="moved \{step}: the host told the caret where it is drawn, as big: \{(x, y, w, h)}")
  }
}

///|
test "an old view hosted in a node drawn half as big, then moved and drawn whole with no frame between: pressed and its caret put down where it is drawn now" {
  // (where a tap 33 along its line puts its caret, whole: another Tester's, before this one's)
  let (whole, _) = hosted_caret(1.0, 33.0)
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let moved = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let field = Field::new(text="abcdefghij")
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(By(fn() { let (dx, dy) = moved.get(); (20.0 + dx, 20.0 + dy) }))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        let b = c.id("old button")
        if c.clicked(b) {
          pressed["button"] = pressed.get("button").unwrap_or(0) + 1
        }
        c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("e", field~, font_size=10.0) |> ignore }) |> ignore
        c.box(dir=Row, w=Px(200.0), h=Px(50.0), fn() {
          c.box(w=Px(100.0), h=Px(50.0), fn() {  }) |> ignore
          c.box(w=Px(100.0), h=Px(50.0), bg=0x3366CCFFL, id=b, fn() {  }) |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (whole, moved 50 across and 40 down, no frame drawn: the button laid out at (100, 20) in it drawn at (170, 80))
  s.set(1.0)
  moved.set((50.0, 40.0))
  t.touch(0, 180.0, 90.0)
  t.touch(2, 180.0, 90.0)
  // (the click counted as the old view is next built)
  t.draw()
  assert_eq(pressed.get("button").unwrap_or(0), 1, msg="pressed where it was drawn as the press came, no frame between")
  // (half again, back where it was, no frame: a press 33 along its line where it is drawn now; as whole)
  s.set(0.5)
  moved.set((0.0, 0.0))
  t.touch(0, 20.0 + 33.0 * 0.5, 20.0 + 5.0)
  t.touch(2, 20.0 + 33.0 * 0.5, 20.0 + 5.0)
  assert_eq(field.selection().1, whole, msg="its caret put down where it is drawn now, no frame between")
  t.draw()
  assert_eq(field.selection().1, whole, msg="drawn: where it was put down")
}

///|
/// A finger on the hosted editor drawn at `scale` (a host that draws handles: Android's): a tap 33 along its line puts
/// its caret down, its handle drawn under it; the handle pressed where it is drawn, the press taken by it and the caret
/// where it was, moved `dx` along (in the editor's own terms) and let go: the caret after.
fn hosted_handle(scale : Double, dx : Double) -> (Int, Int) raise {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let field = Field::new(text="abcdefghij")
  let t = hosted_scaled(s, {}, field, platform=2)
  t.tap(20.0 + 33.0 * scale, 20.0 + 10.0 * scale)
  let st = field.st
  assert_true(st.handle_on, msg="its handle drawn under its caret")
  let before = field.selection().1
  // (the handle's circle under its tip, as placed; drawn about the holder's top left, as big)
  let (cx, cy) = (st.handle_x, st.handle_y + handle_r * 1.4142135623730951)
  let (x, y) = (20.0 + (cx - 20.0) * scale, 20.0 + (cy - 20.0) * scale)
  t.touch(0, x, y)
  assert_true(g().handle_drag != 0 && g().handle_which == 1, msg="pressed: taken by the caret's handle")
  assert_eq(field.selection().1, before, msg="pressed: the caret where it was")
  t.touch(1, x + dx * scale, y)
  t.touch(2, x + dx * scale, y)
  let moved = field.selection().1
  t.draw()
  assert_eq(field.selection().1, moved, msg="drawn: where it was moved")
  (before, moved)
}

///|
test "an editor in an old view hosted in a node drawn half as big, a finger on its caret's handle where it is drawn: pressed, taken by it, the caret where it was; moved, where the same move whole puts it" {
  let (whole_down, whole_moved) = hosted_handle(1.0, 30.0)
  let (half_down, half_moved) = hosted_handle(0.5, 30.0)
  assert_eq(half_down, whole_down, msg="pressed: the caret where it was")
  assert_true(whole_moved != whole_down, msg="whole: moved by its handle: \{whole_down} then \{whole_moved}")
  assert_eq(half_moved, whole_moved, msg="half: moved as whole")
}

///|
/// A finger on the hosted editor drawn at `scale` (Android's host): a double tap 120 along its line picks a word, its
/// two handles drawn; the end's pressed where it is drawn, the press taken by it and the words picked as they were,
/// moved `dx` along (in the editor's own terms) and let go: what is picked, before and after.
fn hosted_sel_handle(scale : Double, dx : Double) -> ((Int, Int), (Int, Int)) raise {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let field = Field::new(text="ab cd ef gh ij kl mn op qr st uv wx yz")
  let t = hosted_scaled(s, {}, field, platform=2)
  // (a word far along its line: where it is drawn half as big far from where it is laid out)
  let (x, y) = (20.0 + 120.0 * scale, 20.0 + 10.0 * scale)
  t.tap(x, y)
  t.tap(x, y)
  let st = field.st
  assert_true(st.sel_on, msg="its words' handles drawn")
  let before = field.selection()
  // (the end's circle, to its tip's right, as placed; drawn about the holder's top left, as big)
  let (cx, cy) = (st.sel_bx + handle_r, st.sel_by + handle_r)
  let (hx, hy) = (20.0 + (cx - 20.0) * scale, 20.0 + (cy - 20.0) * scale)
  t.touch(0, hx, hy)
  assert_true(g().handle_drag != 0 && g().handle_which == 3, msg="pressed: taken by the end's handle")
  assert_eq(field.selection(), before, msg="pressed: what is picked as it was")
  t.touch(1, hx + dx * scale, hy)
  t.touch(2, hx + dx * scale, hy)
  let moved = field.selection()
  t.draw()
  assert_eq(field.selection(), moved, msg="drawn: as it was moved")
  (before, moved)
}

///|
test "an editor in an old view hosted in a node drawn half as big, a finger on its picked words' end handle where it is drawn: pressed, taken by it, the words as they were; moved, what the same move whole picks" {
  let (whole_down, whole_moved) = hosted_sel_handle(1.0, 30.0)
  let (half_down, half_moved) = hosted_sel_handle(0.5, 30.0)
  assert_eq(half_down, whole_down, msg="pressed: the words picked as whole")
  assert_true(whole_moved != whole_down, msg="whole: moved by its handle: \{whole_down} then \{whole_moved}")
  assert_eq(half_moved, whole_moved, msg="half: moved as whole")
}

///|
/// The hosted editor drawn at `scale`, its words double clicked 33 along its line and the pointer dragged on `dx`
/// along (its own terms): what is picked.
fn hosted_widened(scale : Double, dx : Double) -> (Int, Int) {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let field = Field::new(text="ab cd ef gh ij")
  let t = hosted_scaled(s, {}, field)
  t.host_says_finger(Some(false))
  let (x, y) = (20.0 + 33.0 * scale, 20.0 + 10.0 * scale)
  t.tap(x, y)
  t.touch(0, x, y)
  t.touch(1, x + dx * scale, y)
  t.touch(2, x + dx * scale, y)
  t.draw()
  field.selection()
}

///|
test "an editor in an old view hosted in a node drawn half as big: a double click's second press dragged on, words picked as the same whole" {
  let whole = hosted_widened(1.0, 40.0)
  let half = hosted_widened(0.5, 40.0)
  assert_true(whole.0 != whole.1, msg="whole: words picked: \{whole}")
  assert_eq(half, whole, msg="half: the same words")
}

///|
test "an editor in an old view hosted in a node drawn half as big, its caret moved by the keyboard's trackpad by nothing: where it was" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let field = Field::new(text="abcdefghij")
  let t = hosted_scaled(s, {}, field)
  t.tap(20.0 + 33.0 * 0.5, 25.0)
  t.draw()
  let at = field.selection().1
  t.ime_trackpad(100, 100, 100, 100)
  assert_eq(field.selection().1, at, msg="moved by nothing: where it was")
}

///|
test "an editor in an old view hosted in a node, a pointer held down in its words as the node is drawn as nothing, then moved and let go: nothing picked, its caret where the press put it" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let field = Field::new(text="abcdefghij")
  let t = hosted_scaled(s, {}, field)
  t.host_says_finger(Some(false))
  t.touch(0, 20.0 + 33.0 * 0.5, 25.0)
  t.draw()
  let at = field.selection()
  s.set(0.0)
  t.draw()
  t.touch(1, 200.0, 25.0)
  t.touch(2, 200.0, 25.0)
  t.draw()
  assert_eq(field.selection(), at, msg="drawn as nothing: nothing done with the pointer")
}

///|
test "an old view hosted in a node drawn half as big, the mouse's pointer on it: what is under it where it is drawn lit, not what is laid out there; drawn whole, the pointer still, what is laid out under it lit in the first frame so drawn" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let t = hosted_scaled(s, {}, Field::new())
  t.host_says_finger(Some(false))
  let lit = fn() {
    t.drawn_rects().filter(fn(r) { r.4 == hosted_lit }).map(fn(r) { (r.0, r.1, r.2, r.3) })
  }
  // (the button laid out at (120, 40) 100 by 50, drawn at (70, 30) 50 by 25)
  t.move(80.0, 40.0)
  t.draw()
  assert_eq(lit(), [(70.0, 30.0, 50.0, 25.0)], msg="on it where it is drawn: lit")
  t.move(150.0, 60.0)
  t.draw()
  assert_eq(lit(), [], msg="where it is laid out but not drawn: not lit")
  s.set(1.0)
  t.draw()
  assert_eq(lit(), [(120.0, 40.0, 100.0, 50.0)], msg="drawn whole, the pointer still: lit where it is now, in the first frame so drawn")
  // (what a still pointer is looked at again by, the tree's targets changed: unchanged, nothing told it again)
  let said = view_app.val.unwrap().hits_said()
  t.draw()
  t.draw()
  assert_eq(view_app.val.unwrap().hits_said(), said, msg="still frames: nothing placed otherwise said")
  assert_eq(lit(), [(120.0, 40.0, 100.0, 50.0)], msg="still frames: lit as it was")
}

///|
test "an old view hosted in a node drawn half as big, a button in it cut round (its corners' radius 40 of 80): pressed inside its corner's curve as drawn, half as round; not outside it" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let clicks = Ref::new(0)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        let b = c.id("round")
        if c.clicked(b) {
          clicks.val += 1
        }
        c.box(w=Px(80.0), h=Px(80.0), radius=40.0, clip=true, fn() {
          c.box(w=Px(80.0), h=Px(80.0), bg=0x3366CCFFL, id=b, fn() {  }) |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (drawn at (20, 20) 40 by 40, its corners 20 round: (22, 40) 18 from its left curve's middle (40, 40), inside it; as
  // round as laid out, 40, the curve's middle at (60, 60) and (22, 40) 43 from it, outside)
  t.tap(22.0, 40.0)
  t.draw()
  assert_eq(clicks.val, 1, msg="inside its corner's curve as drawn: pressed")
  // ((23, 23) 24 from (40, 40), outside its curve as drawn)
  t.tap(23.0, 23.0)
  t.draw()
  assert_eq(clicks.val, 1, msg="outside its corner's curve as drawn: nothing")
}

///|
test "an old view hosted in a node drawn half as big, a list in it: the wheel scrolls it where it is drawn, not where it is laid out but not drawn; drawn whole with no frame between, where it is laid out; drawn as nothing, nowhere" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        c.list("rows", 30, 40.0, fn(k) {
          c.box(w=Fill(1.0), h=Px(40.0), id=c.id("row \{k}"), fn() { c.text("row \{k}", size=12.0) |> ignore }) |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (laid out at (20, 20) 200 by 100, drawn at (20, 20) 100 by 50)
  let at0 = t.list_offset()
  t.wheel(60.0, 40.0, 120.0)
  t.draw()
  let at1 = t.list_offset()
  assert_true(at1 > at0, msg="where it is drawn: scrolled, \{at0} to \{at1}")
  t.wheel(160.0, 90.0, 120.0)
  t.draw()
  assert_eq(t.list_offset(), at1, msg="where it is laid out but not drawn: not scrolled")
  // (whole, no frame drawn: what is laid out there is drawn there)
  s.set(1.0)
  finger_wheel(160.0, 90.0, 0.0, 120.0, 0)
  t.draw()
  let at2 = t.list_offset()
  assert_true(at2 > at1, msg="whole, no frame between: scrolled where it is laid out, \{at1} to \{at2}")
  s.set(0.0)
  t.draw()
  t.wheel(60.0, 40.0, 120.0)
  t.draw()
  assert_eq(t.list_offset(), at2, msg="drawn as nothing: not scrolled")
}

///|
test "an old view hosted in a node drawn half as big, a list in it: a finger drawn across it where it is drawn scrolls it; where it is laid out but not drawn, not" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        c.list("rows", 30, 40.0, fn(k) {
          c.box(w=Fill(1.0), h=Px(40.0), id=c.id("row \{k}"), fn() { c.text("row \{k}", size=12.0) |> ignore }) |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.host_says_finger(Some(true))
  t.draw()
  let at0 = t.list_offset()
  t.drag(160.0, 115.0, 160.0, 75.0, steps=4)
  t.draw()
  assert_eq(t.list_offset(), at0, msg="where it is laid out but not drawn: not scrolled")
  t.drag(60.0, 65.0, 60.0, 25.0, steps=4)
  t.draw()
  assert_true(t.list_offset() > at0, msg="where it is drawn: scrolled, \{at0} to \{t.list_offset()}")
}

///|
/// A node of the tree's 300 by 200 under all of it, taking presses (counted as "under", its ground `under_lit` while
/// the pointer is on it); over it a holder 200 by 100 at (20, 20) drawn `s` as big about its top left, holding an old
/// view taking a finger only where what it builds takes presses (old_takes_own): a button 100 by 50 laid out at (100,
/// 20) in it (counted as "button", drawn `hosted_lit` while the mouse's pointer is on it).
fn hosted_own(s : @signals.Signal[Double], pressed : Map[String, Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  let count = fn(k : String) { pressed[k] = pressed.get(k).unwrap_or(0) + 1 }
  set_view_app(fn(root) {
    root.box(fn(u) {
      u
      .over(Is(true))
      .width(Is(Some(300.0)))
      .height(Is(Some(200.0)))
      .on_press(fn() { count("under") })
      .ground(By(fn() { if u.pointed() { under_lit } else { 0L } }))
      |> ignore
    })
    |> ignore
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        let button = c.id("old button")
        if c.clicked(button) {
          count("button")
        }
        c.box(w=Px(200.0), h=Px(20.0), fn() {  }) |> ignore
        c.box(dir=Row, w=Px(200.0), h=Px(50.0), fn() {
          c.box(w=Px(100.0), h=Px(50.0), fn() {  }) |> ignore
          c.box(w=Px(100.0), h=Px(50.0), bg=if c.hovered(button) { hosted_lit } else { 0x3366CCFFL }, id=button, fn() {  })
          |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> old_takes_own
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The node under the hosted old view's ground while the pointer is on it.
let under_lit : Int64 = 0x998877FFL

///|
test "an old view taking a finger only where it builds what takes one, hosted in a node drawn half as big over a node of the tree's: its button pressed where it is drawn, what is under it pressed elsewhere; drawn whole with no frame between, where it is laid out" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let t = hosted_own(s, pressed)
  // (the button laid out at (120, 40) 100 by 50, drawn at (70, 30) 50 by 25; in the holder's own terms (120, 40) there)
  t.tap(80.0, 40.0)
  t.draw()
  assert_eq((hosted_pressed(pressed, "button"), hosted_pressed(pressed, "under")), (1, 0), msg="where it is drawn: the button")
  // (in the holder as drawn, not on the button as drawn: (40, 60), in its own terms (40, 80))
  t.tap(40.0, 60.0)
  t.draw()
  assert_eq((hosted_pressed(pressed, "button"), hosted_pressed(pressed, "under")), (1, 1), msg="off it in the holder: what is under it")
  s.set(1.0)
  t.touch(0, 150.0, 60.0)
  t.touch(2, 150.0, 60.0)
  t.draw()
  assert_eq((hosted_pressed(pressed, "button"), hosted_pressed(pressed, "under")), (2, 1), msg="whole, no frame between: the button where it is laid out")
}

///|
test "an old view taking a finger only where it builds what takes one, hosted in a node drawn half as big over a node of the tree's, the mouse's pointer still: lit where it is drawn, what is under it elsewhere; drawn whole, the pointer still, the button lit in the first frame so drawn, what is under it not; still frames after, as they were" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let t = hosted_own(s, {})
  t.host_says_finger(Some(false))
  let lit = fn() {
    let r = t.drawn_rects()
    (
      r.filter(fn(r) { r.4 == hosted_lit }).map(fn(r) { (r.0, r.1, r.2, r.3) }),
      r.any(fn(r) { r.4 == under_lit }),
    )
  }
  t.move(80.0, 40.0)
  t.draw()
  assert_eq(lit(), ([(70.0, 30.0, 50.0, 25.0)], false), msg="on it where it is drawn: it lit, not what is under it")
  t.move(150.0, 60.0)
  t.draw()
  assert_eq(lit(), ([], true), msg="where it is laid out but not drawn: what is under it lit")
  s.set(1.0)
  t.draw()
  assert_eq(lit(), ([(120.0, 40.0, 100.0, 50.0)], false), msg="drawn whole, the pointer still: it lit in the first frame so drawn, not what is under it")
  // (what a still pointer is looked at again by, the tree's targets changed: unchanged, nothing told it again)
  let said = view_app.val.unwrap().hits_said()
  t.draw()
  t.draw()
  assert_eq(view_app.val.unwrap().hits_said(), said, msg="still frames: nothing placed otherwise said")
  assert_eq(lit(), ([(120.0, 40.0, 100.0, 50.0)], false), msg="still frames: as they were")
}

///|
/// A list hosted in an old view in a node drawn `scale` as big at (20, 20) (laid out 200 by 100), for a mouse: wheeled a
/// little where it is drawn, its bar brought out; whether the pointer near its right edge where it is drawn brings it
/// out; its thumb, where it is drawn, pressed (asserted taken by the bar, the list where it was), then (`gone`: the node
/// drawn as nothing, a frame drawn) dragged down 20 of its own terms (20 · `scale` of the window's) and let go: how far
/// it scrolled from where the press found it.
fn hosted_bar(scale : Double, gone? : Bool = false) -> (Bool, Double) raise {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let list = Ref(-1)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        list.val = c.list("rows", 30, 40.0, fn(k) {
          c.box(w=Fill(1.0), h=Px(40.0), id=c.id("row \{k}"), fn() { c.text("row \{k}", size=12.0) |> ignore }) |> ignore
        })
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.host_says_finger(Some(false))
  t.wheel(20.0 + 100.0 * scale, 20.0 + 50.0 * scale, 120.0)
  t.run_for(scrollbar_fade_ms)
  // (its edge where it is drawn: 4 in of its own terms)
  t.move(20.0 + 196.0 * scale, 20.0 + 50.0 * scale)
  t.run_for(scrollbar_fade_ms)
  let near = g().bar_near != 0
  let thumb = t.drawn_rects().filter(fn(r) { r.2 <= scroll_bar_size && r.3 > 3.0 * r.2 && r.0 > 20.0 + 150.0 * scale }).get(0)
  guard thumb is Some((tx, ty, tw, th, _)) else { fail("no thumb drawn") }
  let p = (tx + tw / 2.0, ty + th / 2.0)
  t.move(p.0, p.1)
  let before = t.list_offset()
  t.press_at(p.0, p.1)
  assert_eq(g().bar_drag, g().nodes[list.val].id, msg="pressed: taken by its bar")
  assert_eq(t.list_offset(), before, msg="pressed: the list where it was")
  if gone {
    s.set(0.0)
    t.draw()
  }
  for i in 1..=2 {
    t.move(p.0, p.1 + 10.0 * scale * i.to_double())
    t.run_for(drag_step_ms)
  }
  t.release(p.0, p.1 + 20.0 * scale)
  (near, t.list_offset() - before)
}

///|
test "an old view hosted in a node drawn half as big, a list in it, a mouse's: its bar brought out near its edge where it is drawn; its thumb held where it is drawn and dragged half as far, scrolled as far as whole" {
  let (whole_near, whole_moved) = hosted_bar(1.0)
  let (half_near, half_moved) = hosted_bar(0.5)
  assert_true(whole_near, msg="whole: brought out near its edge")
  assert_true(whole_moved > 0.0, msg="whole: scrolled by its thumb: \{whole_moved}")
  assert_true(half_near, msg="half: brought out near its edge where it is drawn")
  assert_true((half_moved - whole_moved).abs() < 1.0e-6, msg="half: scrolled as far as whole: \{half_moved}, \{whole_moved}")
}

///|
test "an old view hosted in a node drawn half as big, a list in it, its thumb held by a mouse as the node is drawn as nothing, then dragged and let go: not scrolled" {
  let (_, moved) = hosted_bar(0.5, gone=true)
  assert_eq(moved, 0.0, msg="drawn as nothing: not scrolled by its thumb")
}

///|
test "an old view hosted in a node drawn half as big, a native view in it all of it, a button of the old view's over it: the native view placed and its hole cut where it is drawn, as big, the host told the button covers it there; whole again, where it is laid out" {
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  // (opened of the Tester's host)
  let page = NativeView::page("<p>page</p>")
  set_view_app(fn(root) {
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        c.layer(fn() { c.native(page) |> ignore }) |> ignore
        c.layer(fn() {
          let id = c.id("over")
          c.clicked(id) |> ignore
          c.box(w=Px(80.0), h=Px(40.0), tx=100.0, id~, fn() {  }) |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame_at(t.time() + frame_period_default)
  // (where the host was last told it is placed, and the hole cut for it, each as x y w h)
  let placed = fn() {
    match t.views().iter().filter(fn(l) { l.has_prefix("place \{page.id} ") }).last() {
      Some(l) => {
        let w = l.split(" ").map(fn(v) { v.to_string() }).collect()
        (said_number(w[2]), said_number(w[3]), said_number(w[4]), said_number(w[5]))
      }
      None => (-1.0, -1.0, -1.0, -1.0)
    }
  }
  let half = fn(r : (Double, Double, Double, Double)) { (20.0 + (r.0 - 20.0) * 0.5, 20.0 + (r.1 - 20.0) * 0.5, r.2 * 0.5, r.3 * 0.5) }
  let whole_at = placed()
  let whole_holes = t.holes()
  assert_true(whole_at.2 > 0.0 && whole_holes.length() == 1, msg="whole: placed \{whole_at}, its hole \{whole_holes}")
  // (the button laid out at (120, 20) 80 by 40)
  assert_eq(covers_of(page), [120.0, 20.0, 200.0, 60.0], msg="whole: where it is laid out")
  s.set(0.5)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(covers_of(page), [70.0, 20.0, 110.0, 40.0], msg="half: where it is drawn, as big, the first frame so drawn")
  assert_eq(placed(), half(whole_at), msg="half: placed where it is drawn, as big")
  assert_eq(t.holes(), whole_holes.map(half), msg="half: its hole where it is drawn, as big")
  s.set(1.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(covers_of(page), [120.0, 20.0, 200.0, 60.0], msg="whole again: where it is laid out")
  assert_eq(placed(), whole_at, msg="whole again: placed where it is laid out")
  assert_eq(t.holes(), whole_holes, msg="whole again: its hole where it is laid out")
}

///|
/// A card of the tree, 200×120, its ground 20 round, 6 in all round, drawn `s` as big, holding an old view all of what
/// it holds (188×108), a box across its top, 60 high, `r` round (in the card's top corners alone: not made concentric
/// with them as it is laid out, what the rule says of it as it is).
fn hosted_card(s : @signals.Signal[Double], r : Double) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card
      .width(Is(Some(200.0)))
      .height(Is(Some(120.0)))
      .pad(Is(6.0))
      .ground(Is(0x333333FFL))
      .radius(Is(20.0))
      .scale(By(fn() { s.get() }))
      |> ignore
      card.box(fn(v) {
        v.width(Is(Some(188.0))).height(Is(Some(108.0))) |> ignore
        old(v, fn(c) { c.box(w=Fill(1.0), h=Px(60.0), radius=r, bg=0xEEEEEEFFL, fn() {  }) |> ignore }).grow(Is(1.0))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "corners of an old view hosted in a card drawn whole, half as big, whole again: its box concentric with the card as laid out, nothing said each time; one 20 round in it said each time, wanting the card's concentric corner as drawn" {
  let follow = concentric(20.0, 6.0)
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let right = hosted_card(s, follow)
  let seen_right = [right.corner_faults()]
  s.set(0.5)
  right.draw()
  seen_right.push(right.corner_faults())
  s.set(1.0)
  right.draw()
  seen_right.push(right.corner_faults())
  assert_eq(seen_right, [[], [], []], msg="concentric as laid out: nothing said")
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let wrong = hosted_card(s, 20.0)
  let whole = wants(wrong.corner_faults(), follow)
  s.set(0.5)
  wrong.draw()
  // (the frame's nodes as they were after: where each is, how big and round, what holds it and what follows it)
  let c = g()
  let nodes = fn() {
    Array::makei(c.count, fn(i) {
      let n = c.nodes[i]
      (n.x, n.y, n.fw, n.fh, n.radius, n.radii.map(fn(r) { Array::makei(r.length(), fn(k) { r[k] }) }), n.tx, n.ty, n.border_w, n.parent, n.first, n.next)
    })
  }
  let before = nodes()
  let half = wrong.corner_faults()
  assert_true(nodes() == before, msg="half: the frame's nodes as they were after")
  s.set(1.0)
  wrong.draw()
  let again = wants(wrong.corner_faults(), follow)
  assert_eq((whole, wants(half, concentric(10.0, 3.0)), again), (true, true, true), msg=half.join("\n"))
}

///|
/// A number as a host was told it (-1: none).
fn said_number(v : String) -> Double {
  match (try Some(@json.parse(v)) catch { _ => None }) {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
}

///|
test "a press's room in an old view hosted in a node drawn whole, half as big, whole again, two buttons 44 across side by side in it on a host a finger is native to: room enough whole; drawn 22 across, too little, said where they are drawn; whole again, enough" {
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(100.0)))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      old(h, fn(c) {
        c.box(dir=Row, w=Px(200.0), h=Px(44.0), fn() {
          for k in ["a", "b"] {
            let id = c.id(k)
            c.clicked(id) |> ignore
            c.box(w=Px(44.0), h=Px(44.0), bg=0x3366CCFFL, id~, fn() {  }) |> ignore
          }
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let whole = t.room_faults()
  s.set(0.5)
  t.draw()
  let half = t.room_faults()
  s.set(1.0)
  t.draw()
  let again = t.room_faults()
  assert_eq(whole, [], msg="whole: room enough")
  // (drawn at (20, 20) and (42, 20), 22 across)
  let said = fn(at : String) { half.iter().any(fn(f) { f.has_prefix("room: ") && f.contains(at) }) }
  assert_true(
    half.length() == 2 && said("at 20,20 22×22") && said("at 42,20 22×22"),
    msg="half: too little room for each, said where it is drawn, as big, nothing else: \{half}",
  )
  assert_eq(again, [], msg="whole again: room enough")
}

///|
test "an old view hosted in a node whole inside one drawn a little smaller (0.99, what holds it scaled, it offset in it): drawn, its words, read out, pressed and its editor's caret told where that scale puts it, not its top left moved onto the pixels" {
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let field = Field::new(text="abcdefghij")
  let t = hosted_scaled(s, pressed, field, nested=true)
  // (its editor focused, its caret at its start, whole: where the host is told it is)
  t.tap(41.0, 50.0)
  t.draw()
  field.set(field.text(), caret=0)
  t.draw()
  let (x, y, w, h) = t.ime_rect()
  let g3 = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  // (its words whole, and where they go drawn 0.99 as big about the window's top left: set on the pixels where they
  // are laid out, then scaled with the rest)
  let words_scaled = t.drawn_glyphs().map(fn(q) { (g3(q.0 * 0.99), g3(q.1 * 0.99)) })
  // (the button laid out at (140, 60) in the window, 100 by 50, in what is drawn 0.99 as big about the window's top
  // left: drawn at (138.6, 59.4), 99 by 49.5, as the tree draws what it holds there; its holder's top left (39.6, 39.6)
  // on no pixel (the Tester's two to a point), 39.5 were it moved onto one)
  s.set(0.99)
  t.draw()
  let f = fn(r : (Double, Double, Double, Double)) {
    let g = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
    (g(r.0), g(r.1), g(r.2), g(r.3))
  }
  let blue = t.drawn_rects().filter(fn(r) { r.4 == 0x3366CCFFL }).map(fn(r) { f((r.0, r.1, r.2, r.3)) })
  let read = f(t.get(Button, label="old button").rect)
  let caret = f(t.ime_rect())
  let words = t.drawn_glyphs().map(fn(q) { (g3(q.0), g3(q.1)) })
  // (pressed just left of where it is drawn: nothing; just right of its left edge: it)
  t.tap(138.55, 80.0)
  t.draw()
  let outside = hosted_pressed(pressed, "button")
  t.tap(138.65, 80.0)
  t.draw()
  let inside = hosted_pressed(pressed, "button")
  assert_eq(
    (blue, read, caret, words, outside, inside),
    ([(138.6, 59.4, 99.0, 49.5)], (138.6, 59.4, 99.0, 49.5), f((x * 0.99, y * 0.99, w * 0.99, h * 0.99)), words_scaled, 0, 1),
  )
}

///|
/// An old view 200 by 100 at (40, 40) in a node at the window's top left drawn 0.99 as big about it: its words on a box
/// 200 by 30 at its top (put off till the frame's end where `flying`: a Stratum's Flying), a node 20 by 20 over it after
/// it at (250, 150). Its words as drawn, how many times its box and that node are drawn, and whether its box is drawn
/// after that node.
fn hosted_words_flying(flying : Bool) -> (Array[(Double, Double)], (Int, Int), Bool) {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(200.0))).scale(Is(0.99), about=At(0.0, 0.0)) |> ignore
      o.box(fn(h) {
        h.over(Is(true)).offset(Is((40.0, 40.0))).width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
        old(h, fn(c) {
          let f = c.box(w=Px(200.0), h=Px(30.0), bg=0x336699FFL, fn() { c.text("words that fly", wrap=false) |> ignore })
          if flying {
            c.stratum(f, Flying)
          }
        }).grow(Is(1.0))
        |> ignore
      })
      |> ignore
      o.box(fn(b) {
        b.over(Is(true)).offset(Is((250.0, 150.0))).width(Is(Some(20.0))).height(Is(Some(20.0))).ground(Is(0xCC3333FFL))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  let g3 = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let rects = t.drawn_rects()
  // (how many times each is drawn, and where the first is in the order)
  let times = fn(colour : Int64) { rects.filter(fn(r) { r.4 == colour }).length() }
  let at = fn(colour : Int64) { rects.search_by(fn(r) { r.4 == colour }).unwrap_or(-1) }
  (
    t.drawn_glyphs().map(fn(q) { (g3(q.0), g3(q.1)) }),
    (times(0x336699FFL), times(0xCC3333FFL)),
    at(0x336699FFL) > at(0xCC3333FFL),
  )
}

///|
test "an old view hosted in a node drawn a little smaller (0.99), its words in a box put off till the frame's end (Flying): drawn after what is over it, its words where they are drawn painted at once" {
  let (at_once, drawn, after) = hosted_words_flying(false)
  let (put_off, put_off_drawn, put_off_after) = hosted_words_flying(true)
  assert_eq(
    (at_once.length() > 0, drawn, put_off_drawn, after, put_off_after, put_off),
    (true, (1, 1), (1, 1), false, true, at_once),
  )
}
