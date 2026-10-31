// An old view in the window's tree laid out where its layout alone puts it (Tree::laid_origin) and moved to where it is
// drawn as the frame is painted (view_host.mbt old_frame): what moves or fades it, or what holds it (an offset, a page
// slid by its width), paints the frame alone (Tester's own check drawing it whole after and comparing, as in every
// test), drawn as building it whole draws it, pressed where it is drawn; what lays it out elsewhere (its holder's
// padding) builds it again. What a frame of it costs is measured as a host draws it, with no such check (appbench).

///|
/// A window 400 by 200 whose tree holds, 30 in and 10 down by its padding (`pad`), an old view 300 by 150 moved by `at`
/// and as opaque as `alpha`: in it, words and a button 80 by 40 at its origin, its presses counted in `clicks`.
fn island_moved_tester(
  at : @signals.Signal[(Double, Double)],
  alpha : @signals.Signal[Double],
  pad : @signals.Signal[Double],
  clicks : Ref[Int],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(400.0)))
      .height(Is(Some(200.0)))
      .padding(By(fn() { (pad.get(), 10.0, 0.0, 0.0) }))
      |> ignore
      old(b, fn(c) {
        c.box(w=Px(300.0), h=Px(150.0), fn() {
          let id = c.id("go")
          if c.clicked(id) {
            clicks.val = clicks.val + 1
          }
          c.box(w=Px(80.0), h=Px(40.0), id~, fn() { c.text("go words", wrap=false) |> ignore }) |> ignore
        })
        |> ignore
      })
      .width(Is(Some(300.0)))
      .height(Is(Some(150.0)))
      .offset(By(fn() { at.get() }))
      .alpha(By(fn() { alpha.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (laid out the same twice: what comes after it may be painted alone)
  t.clock_frame()
  t.clock_frame()
  t
}

///|
/// A frame drawn after `change`: whether it was painted alone (nothing built nor laid out: paints_alone counted, the
/// Tester's own check drawing it whole after it and comparing as ever), its picture's hash, and its picture as the frame
/// built whole draws it.
fn island_frame(t : Tester, change : () -> Unit) -> (Bool, Int64, Int64) {
  change()
  let was = paints_alone.val
  t.clock_frame()
  let alone = paints_alone.val - was == 1
  let drawn = t.frame_hash()
  t.draw()
  (alone, drawn, t.frame_hash())
}

///|
/// Whether a press at (x, y) presses the old view's button (the frames after it drawn till nothing more comes of it).
fn island_pressed(t : Tester, clicks : Ref[Int], x : Double, y : Double) -> Bool {
  let was = clicks.val
  t.press_at(x, y)
  t.release(x, y)
  t.draw()
  t.clock_frame()
  t.clock_frame()
  clicks.val == was + 1
}

///|
test "an old view laid out 30 in by its holder's padding, moved by an offset twice: each frame painted alone, drawn as built whole, pressed where it is drawn" {
  let at = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
  let clicks = Ref(0)
  let t = island_moved_tester(
    at,
    @signals.signal(1.0, same=fn(a, b) { a == b }),
    @signals.signal(30.0, same=fn(a, b) { a == b }),
    clicks,
  )
  let (a1, d1, w1) = island_frame(t, fn() { at.set((20.0, 10.0)) })
  let p1 = island_pressed(t, clicks, 30.0 + 20.0 + 40.0, 10.0 + 10.0 + 20.0)
  let (a2, d2, w2) = island_frame(t, fn() { at.set((60.0, 40.0)) })
  // (where it was before, nothing; where it is now, its button)
  let gone = island_pressed(t, clicks, 30.0 + 20.0 + 5.0, 10.0 + 10.0 + 5.0)
  let p2 = island_pressed(t, clicks, 30.0 + 60.0 + 40.0, 10.0 + 40.0 + 20.0)
  assert_eq(
    (a1, d1 == w1, p1, a2, d2 == w2, gone, p2),
    (true, true, true, true, true, false, true),
    msg=t.built_why(),
  )
}

///|
test "an old view faded by its node: painted alone, drawn as built whole" {
  let alpha = @signals.signal(1.0, same=fn(a, b) { a == b })
  let t = island_moved_tester(
    @signals.signal((0.0, 0.0), same=fn(a, b) { a == b }),
    alpha,
    @signals.signal(30.0, same=fn(a, b) { a == b }),
    Ref(0),
  )
  let opaque = t.frame_hash()
  let (alone, drawn, whole) = island_frame(t, fn() { alpha.set(0.5) })
  assert_eq((alone, drawn == whole, drawn != opaque), (true, true, true), msg=t.built_why())
}

///|
test "an old view laid out elsewhere by its holder's padding: built and laid out again there, drawn as built whole, pressed there" {
  let pad = @signals.signal(30.0, same=fn(a, b) { a == b })
  let clicks = Ref(0)
  let t = island_moved_tester(
    @signals.signal((20.0, 10.0), same=fn(a, b) { a == b }),
    @signals.signal(1.0, same=fn(a, b) { a == b }),
    pad,
    clicks,
  )
  let (alone, drawn, whole) = island_frame(t, fn() { pad.set(70.0) })
  let pressed = island_pressed(t, clicks, 70.0 + 20.0 + 40.0, 10.0 + 10.0 + 20.0)
  assert_eq((alone, drawn == whole, pressed), (false, true, true), msg=t.built_why())
}

///|
/// A touch window 400 by 200 whose tree holds, 30 in and 10 down by its padding, an old view drawn moved by `at` (an
/// offset that stays): in it, two keys 20 by 20 side by side, each pressed (read clicked), too close for each to have
/// 44 across. The room faults, the old view's keys first.
fn island_rooms(at : (Double, Double)) -> Array[String] {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(400.0))).height(Is(Some(200.0))).padding(Is((30.0, 10.0, 0.0, 0.0))) |> ignore
      old(b, fn(c) {
        c.box(w=Px(300.0), h=Px(150.0), align=AStart, fn() {
          c.box(dir=Row, fn() {
            for k in 0..<2 {
              let id = c.id("key \{k}")
              c.clicked(id) |> ignore
              c.box(w=Px(20.0), h=Px(20.0), id~, fn() {  }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      .width(Is(Some(300.0)))
      .height(Is(Some(150.0)))
      .offset(Is(at))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.clock_frame()
  t.room_faults()
}

///|
test "an old view laid out 30 in by its holder's padding, its two keys too close for a press's room: said where drawn, the old view still or moved by an offset that stays" {
  let says = fn(faults : Array[String], at : String) { faults.iter().any(fn(f) { f.contains("room:") && f.contains(at) }) }
  let still = island_rooms((0.0, 0.0))
  let moved = island_rooms((20.0, 10.0))
  assert_eq(
    (says(still, "at 30,10 20×20"), says(still, "at 50,10 20×20"), says(moved, "at 50,20 20×20"), says(moved, "at 70,20 20×20")),
    (true, true, true, true),
    msg=(still + ["--"] + moved).join("\n"),
  )
}

///|
/// A window 400 by 200 whose tree holds, 30 in and 10 down by its padding, an old view drawn moved by `at`: in it a
/// button read out as 「go」, 80 by 40, and under it a field. The tester.
fn island_read(at : @signals.Signal[(Double, Double)], field : Field) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(400.0))).height(Is(Some(200.0))).padding(Is((30.0, 10.0, 0.0, 0.0))) |> ignore
      old(b, fn(c) {
        c.box(w=Px(300.0), h=Px(150.0), align=AStart, fn() {
          let id = c.id("go")
          c.clicked(id) |> ignore
          let k = c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  })
          c.semantics(k, Button, id~, label="go")
          c.editor("field", field~, font_size=10.0) |> ignore
        })
        |> ignore
      })
      .width(Is(Some(300.0)))
      .height(Is(Some(150.0)))
      .offset(By(fn() { at.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.clock_frame()
  t
}

///|
test "an old view laid out 30 in by its holder's padding, drawn moved by an offset, then moved again: what it says read out where it is drawn, its field's caret told the host there" {
  let at = @signals.signal((20.0, 10.0), same=fn(a, b) { a == b })
  let field = Field::new()
  let t = island_read(at, field)
  let go = fn() {
    match t.all(Button, label="go") {
      [s] => s.rect
      _ => (-1.0, -1.0, -1.0, -1.0)
    }
  }
  let first = go()
  // (the field under the button, where it is drawn: tapped there, a letter typed, the caret told the host)
  t.tap(30.0 + 20.0 + 10.0, 10.0 + 10.0 + 40.0 + 8.0)
  t.type_text("a")
  t.draw()
  let caret = t.ime_rect()
  at.set((60.0, 40.0))
  // (as the frame the move comes in is drawn, not only once a frame built whole after it is)
  t.clock_frame()
  let second = go()
  let caret2 = t.ime_rect()
  t.draw()
  let whole = go()
  let caret3 = t.ime_rect()
  assert_eq(
    (first, second, field.text(), caret2.0 - caret.0, caret2.1 - caret.1, whole == second, caret3 == caret2),
    ((50.0, 20.0, 80.0, 40.0), (90.0, 50.0, 80.0, 40.0), "a", 40.0, 30.0, true, true),
    msg="caret \{caret} then \{caret2}, built whole \{caret3}",
  )
}
