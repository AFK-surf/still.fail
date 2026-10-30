// Two old views in the window's tree (view_host.mbt `old`), side by side: each built for its own room and place, cut to
// it, as opaque as its node, pressed where it is; one's change builds it alone, the other kept as it was; one let go,
// the other goes on, what the one read no longer followed.

///|
let islands_green : Int64 = 0x33AA55FFL

///|
let islands_red : Int64 = 0xCC3333FFL

///|
priv struct Islands {
  t : Tester
  a : @signals.Signal[String]
  b : @signals.Signal[String]
  on_a : @signals.Signal[Bool]
  builds_a : Ref[Int]
  builds_b : Ref[Int]
  taps_b : Ref[Int]
}

///|
/// Old view A (green, its words `a`) in the left half while `on_a` holds; old view B (red, its words `b`, pressed:
/// `taps_b`) in the rest, half opaque; parts kept as their nodes.
fn islands() -> Islands {
  let a = @signals.signal("甲一", same=fn(x, y) { x == y })
  let b = @signals.signal("乙一", same=fn(x, y) { x == y })
  let on_a = @signals.signal(true, same=fn(x, y) { x == y })
  let builds_a = Ref(0)
  let builds_b = Ref(0)
  let taps_b = Ref(0)
  let view_a = fn(c : Ctx) {
    builds_a.val = builds_a.val + 1
    c.box(w=Fill(1.0), h=Fill(1.0), bg=islands_green, fn() { c.text(a.get(), size=12.0) |> ignore }) |> ignore
  }
  let view_b = fn(c : Ctx) {
    builds_b.val = builds_b.val + 1
    let id = c.id("b")
    if c.clicked(id) {
      taps_b.val = taps_b.val + 1
    }
    // (wider than its room: cut to it)
    c.box(w=Px(400.0), h=Fill(1.0), bg=islands_red, id~, fn() { c.text(b.get(), size=12.0) |> ignore }) |> ignore
  }
  let t = Tester::new(fn(_c) {  })
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.show(fn() { on_a.get() }, fn(v) {
      v.width(Is(Some(195.0))) |> ignore
      old(v, view_a).grow(Is(1.0)) |> ignore
    })
    root.box(fn(v) {
      v.grow(Is(1.0)).alpha(Is(0.5)) |> ignore
      old(v, view_b).grow(Is(1.0)) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  { t, a, b, on_a, builds_a, builds_b, taps_b }
}

///|
/// The rectangles drawn of `colour` (its alpha aside): where, how big, how opaque (0-255).
fn rects_of(t : Tester, colour : Int64) -> Array[(Double, Double, Double, Double, Int64)] {
  t.drawn_rects().filter(fn(r) { r.4 >> 8 == colour >> 8 }).map(fn(r) { (r.0, r.1, r.2, r.3, r.4 & 0xFFL) })
}

///|
test "window tree: two old views side by side: each in its own room and place, cut to it, as opaque as its node" {
  let w = islands()
  assert_eq(rects_of(w.t, islands_green), [(0.0, 0.0, 195.0, 844.0, 255L)])
  let red = rects_of(w.t, islands_red)
  assert_true(red.length() == 1 && red[0].0 == 195.0 && red[0].4 >= 126L && red[0].4 <= 129L, msg="\{red}")
  // (wider than its room, cut to it)
  let clip = w.t.drawn_instances().filter(fn(i) { i[5] == 0.0 && i[0] == 195.0 && i[2] == 400.0 })
  assert_true(clip.length() == 1 && clip[0][18] <= 390.0, msg="\{clip.map(fn(i) { (i[16], i[17], i[18], i[19]) })}")
}

///|
test "window tree: one old view's words changed: it alone built again, the other kept as it was" {
  let w = islands()
  let (a0, b0) = (w.builds_a.val, w.builds_b.val)
  w.a.set("甲二")
  w.t.drawn_now()
  assert_eq(w.builds_a.val, a0 + 1)
  assert_eq(w.builds_b.val, b0)
  w.b.set("乙二")
  w.t.drawn_now()
  assert_eq(w.builds_a.val, a0 + 1)
  assert_eq(w.builds_b.val, b0 + 1)
}

///|
test "window tree: a press on the second old view is its own, the first not built for it" {
  let w = islands()
  let (a0, b0) = (w.builds_a.val, w.builds_b.val)
  tree_tap(w.t, 300.0, 400.0)
  assert_eq(w.taps_b.val, 1)
  // (the press built the one it went to, the other kept as it was)
  assert_true(w.builds_b.val > b0)
  assert_eq(w.builds_a.val, a0)
}

///|
test "window tree: one old view let go: what it read no longer followed, the other drawn on in the room left it" {
  let w = islands()
  assert_true(w.a.watched())
  w.on_a.set(false)
  // (let go with the change that let its node go: no frame needed)
  assert_false(w.a.watched())
  w.t.drawn_now()
  let built = w.builds_a.val
  w.a.set("甲三")
  w.t.drawn_now()
  assert_eq(w.builds_a.val, built)
  assert_eq(rects_of(w.t, islands_green), [])
  let red = rects_of(w.t, islands_red)
  assert_true(red.length() == 1 && red[0].0 == 0.0, msg="\{red}")
  assert_true(w.b.watched())
}

///|
/// Old view A (in the left half while `on_a` holds) whose words are in a kept part of their own and in a list's row,
/// both reading `s`; old view B reading `s2`; parts kept as their nodes. `whole`: A alone, the whole window.
fn owning(on_a : @signals.Signal[Bool], s : @signals.Signal[Int], s2 : @signals.Signal[Int], whole : Bool) -> Tester {
  let view_a = fn(c : Ctx) {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.kept_part(c.id("part"), "part", fn() { c.text("part \{s.get()}", size=12.0) |> ignore })
      c.list("rows", 1, 20.0, fn(_) { c.text("row \{s.get()}", size=12.0) |> ignore }) |> ignore
    })
    |> ignore
  }
  let view_b = fn(c : Ctx) { c.text("b \{s2.get()}", size=12.0) |> ignore }
  let t = Tester::new(fn(_c) {  })
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.show(fn() { on_a.get() }, fn(v) {
      v.grow(Is(1.0)) |> ignore
      old(v, view_a).grow(Is(1.0)) |> ignore
    })
    if !whole {
      root.box(fn(v) {
        v.grow(Is(1.0)) |> ignore
        old(v, view_b).grow(Is(1.0)) |> ignore
      })
      |> ignore
    }
  })
  t.draw()
  t.drawn_now()
  t
}

///|
test "window tree: an old view let go: what its parts and rows followed let go with it at once, the other's not" {
  let on_a = @signals.signal(true, same=fn(a, b) { a == b })
  let s = @signals.signal(0)
  let s2 = @signals.signal(0)
  owning(on_a, s, s2, false) |> ignore
  assert_true(s.watched() && s2.watched())
  on_a.set(false)
  assert_false(s.watched())
  assert_true(s2.watched())
}

///|
test "window tree: the one old view, the whole window, let go: what it followed let go at once" {
  let on_a = @signals.signal(true, same=fn(a, b) { a == b })
  let s = @signals.signal(0)
  owning(on_a, s, @signals.signal(0), true) |> ignore
  assert_true(s.watched())
  on_a.set(false)
  assert_false(s.watched())
}
