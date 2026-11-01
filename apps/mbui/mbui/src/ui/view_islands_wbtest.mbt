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
test "window tree: a press on the last old view changes what the first read (itself), built before it: the frame it is taken in draws the first so, the one between that read nothing of it not built again" {
  islands_read_late("itself")
}

///|
test "window tree: a press on the last old view changes what the first read (a part kept in it), built before it: the frame it is taken in draws the first so, the one between that read nothing of it not built again" {
  islands_read_late("a part")
}

///|
test "window tree: a press on the last old view changes what the first read (a part kept in a part kept in it), built before it: the frame it is taken in draws the first so, the one between that read nothing of it not built again" {
  islands_read_late("a part in a part")
}

///|
test "window tree: a press on the last old view changes what the first read (its list's row), built before it: the frame it is taken in draws the first so, the one between that read nothing of it not built again" {
  islands_read_late("a list's row")
}

///|
test "window tree: a press taken in a list's row of the last old view (built as it is laid out) changes what the first read, built before it: the frame it is taken in draws the first so, the one between not built again" {
  islands_read_late("itself", in_row=true)
}

///|
/// Old views A, C and B side by side, B's press setting the colour A reads (`where_read`: in A's build itself, in a
/// part kept in it, in a part kept in that, in its list's one row, each its own watch's): A drawn so in the frame the
/// press is taken in, C built no more, the press taken once. `in_row`: B's press taken in its list's one row (built as
/// it is laid out, after A and C are built).
fn islands_read_late(where_read : String, in_row? : Bool = false) -> Unit raise {
  let colour = @signals.signal(islands_green, same=fn(x, y) { x == y })
  let view_a = fn(c : Ctx) {
    let body = fn() { c.box(w=Fill(1.0), h=Px(100.0), bg=colour.get(), fn() {  }) |> ignore }
    match where_read {
      "a part" => c.kept_part(c.id("a-part"), "", body)
      "a part in a part" => c.kept_part(c.id("a-part"), "", fn() { c.kept_part(c.id("a-inner"), "", body) })
      "a list's row" => c.list("a-rows", 1, 100.0, fn(_) { body() }) |> ignore
      _ => body()
    }
  }
  let builds_c = Ref(0)
  let view_c = fn(c : Ctx) {
    builds_c.val = builds_c.val + 1
    c.box(w=Fill(1.0), h=Fill(1.0), bg=islands_green, fn() {  }) |> ignore
  }
  let taps = Ref(0)
  let view_b = fn(c : Ctx) {
    let pressed = fn() {
      let id = c.id("b")
      if c.clicked(id) {
        taps.val = taps.val + 1
        colour.set(islands_red)
      }
      c.box(w=Fill(1.0), h=Px(800.0), id~, fn() {  }) |> ignore
    }
    if in_row {
      c.list("b-rows", 1, 800.0, fn(_) { pressed() }) |> ignore
    } else {
      pressed()
    }
  }
  let t = Tester::new(fn(_c) {  })
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(v) {
      v.width(Is(Some(130.0))) |> ignore
      old(v, view_a).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.width(Is(Some(130.0))) |> ignore
      old(v, view_c).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.grow(Is(1.0)) |> ignore
      old(v, view_b).grow(Is(1.0)) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  let c0 = builds_c.val
  // (each frame drawn: whether the press was taken, what the first is drawn in, how many times the one between was
  // built)
  let frames : Array[(Int, Array[Int64], Int)] = []
  t.each_frame(
    Some(fn() { frames.push((taps.val, t.drawn_rects().filter(fn(r) { r.0 == 0.0 && r.2 == 130.0 }).map(fn(r) { r.4 }), builds_c.val - c0)) }),
  )
  tree_tap(t, 300.0, 400.0)
  t.each_frame(None)
  let taken = frames.filter(fn(f) { f.0 == 1 })
  assert_true(taken.length() > 0, msg="\{where_read}, in a row \{in_row}: the press not taken: \{frames}")
  assert_eq(taken[0].1, [islands_red], msg="\{where_read}, in a row \{in_row}: the frame the press was taken in: \{frames}")
  assert_eq(taken[0].2, 0, msg="\{where_read}, in a row \{in_row}: the one between, built again in the frame the press was taken in: \{frames}")
  assert_eq(taps.val, 1, msg="\{where_read}, in a row \{in_row}: the press taken once: \{frames}")
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

///|
test "window tree: two old views, then one the whole window, then none: what each read let go as it goes" {
  let on_a = @signals.signal(true, same=fn(a, b) { a == b })
  let on_b = @signals.signal(true, same=fn(a, b) { a == b })
  let s = @signals.signal(0)
  let s2 = @signals.signal(0)
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.show(fn() { on_a.get() }, fn(v) {
      v.grow(Is(1.0)) |> ignore
      old(v, fn(c) { c.text("a \{s.get()}", size=12.0) |> ignore }).grow(Is(1.0)) |> ignore
    })
    root.show(fn() { on_b.get() }, fn(v) {
      v.grow(Is(1.0)) |> ignore
      old(v, fn(c) { c.text("b \{s2.get()}", size=12.0) |> ignore }).grow(Is(1.0)) |> ignore
    })
  })
  t.draw()
  assert_true(s.watched() && s2.watched())
  on_a.set(false)
  t.drawn_now()
  // (B the whole window now)
  assert_false(s.watched())
  assert_true(s2.watched())
  on_b.set(false)
  assert_false(s2.watched())
}

///|
test "window tree: an old view made and let go before any frame lets go of nothing of another's" {
  let on_c = @signals.signal(false, same=fn(a, b) { a == b })
  let s = @signals.signal(0)
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) { c.text("a \{s.get()}", size=12.0) |> ignore }).grow(Is(1.0)) |> ignore
    root.show(fn() { on_c.get() }, fn(v) { old(v, fn(c) { c.text("c", size=12.0) |> ignore }) |> ignore })
  })
  t.draw()
  assert_true(s.watched())
  on_c.set(true)
  on_c.set(false)
  assert_true(s.watched())
}

///|
test "window tree: a kept part made in one old view, then in another in its place with the same key: it follows what it reads there, and is let go with it at once" {
  // (0: old view A, 1: old view B in its place, 2: neither)
  let which = @signals.signal(0, same=fn(a, b) { a == b })
  let s = @signals.signal(0, same=fn(a, b) { a == b })
  let build = fn(c : Ctx) {
    c.kept_part(c.id("part"), "part", fn() { c.text("part \{s.get()}", size=12.0) |> ignore })
  }
  let t = Tester::new(fn(_c) {  })
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { which.get() == 0 }, fn(v) { old(v, build).over(Is(true)) |> ignore })
    root.show(fn() { which.get() == 1 }, fn(v) { old(v, build).over(Is(true)) |> ignore })
  })
  t.draw()
  t.drawn_now()
  which.set(1)
  t.drawn_now()
  // (what it reads changed: drawn so, by B's)
  s.set(1)
  t.drawn_now()
  let words = t.words().filter(fn(w) { w.0.has_prefix("part") }).map(fn(w) { w.0 })
  assert_eq(words, ["part 1"])
  // (B let go: what its part read let go with it, no frame needed)
  assert_true(s.watched())
  which.set(2)
  assert_false(s.watched())
}
