// A node that yields to the list's thumb of an old view under it (yield_thumbs): an edge over the right of a list an old
// view draws, the list's thumb shown for a mouse under the edge's strip the thumb's, nothing else of it; what is over
// the edge there its own, a finger's the edge's, the old view gone what follows none of it.

///|
/// An old view's list (300 wide, 50 rows of 40, in a box cut to its corners as round as `round` says) and over its
/// right an edge of the tree's (12 wide from 290, the window's height) that yields to its thumb, and `cover` a button
/// of the tree's over that (290 to 310, all its height) when it is set; `there` the old view while set. What the edge, the button and the list were told, as `steps` go after the
/// list's thumb is brought out (the list wheeled a little, a mouse's, then the pointer at the thumb).
fn yield_run(
  steps : (Tester, (Double, Double), @signals.Signal[Bool]) -> Unit raise,
  cover? : Bool = false,
  platform? : Int = 0,
  round? : @signals.Signal[Double] = @signals.signal(0.0),
) -> (Array[String], Double) raise {
  let said : Array[String] = []
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform~)
  t.check_looks(false)
  set_view_app(fn(root) {
    let island : Ref[@view.View?] = Ref(None)
    root.show(fn() { there.get() }, fn(b) {
      b.over(Is(true)) |> ignore
      island.val = Some(
        old(b, fn(c) {
          c.box(w=Px(300.0), h=Fill(1.0), radius=round.get(), clip=true, fn() {
            c.list("rows", 50, 40.0, fn(i) { c.box(h=Px(40.0), fn() { c.text("row \{i}", size=10.0) |> ignore }) |> ignore })
            |> ignore
          })
          |> ignore
        }).grow(Is(1.0))
        |> old_takes_own,
      )
    })
    root.box(fn(e) {
      yield_edge.val = Some(e.id())
      e
      .over(Is(true))
      .offset(Is((290.0, 0.0)))
      .width(Is(Some(12.0)))
      .gesture(
        4.0,
        press=fn(_) { said.push("edge press") },
        tap=fn(_) { said.push("edge tap") },
        drag=fn(d) { said.push("edge drag \{d.kind}") },
      )
      |> ignore
      match island.val {
        Some(i) => yield_thumbs(e, i)
        None => ()
      }
    })
    |> ignore
    if cover {
      root.box(fn(k) {
        k
        .over(Is(true))
        .offset(Is((290.0, 0.0)))
        .width(Is(Some(20.0)))
        .height(Is(Some(300.0)))
        .on_press(fn() { said.push("button press") })
        .gesture(4.0, tap=fn(_) { said.push("button tap") }, drag=fn(d) { said.push("button drag \{d.kind}") })
        |> ignore
      })
      |> ignore
    }
  })
  t.draw()
  t.host_says_finger(Some(false))
  t.wheel(150.0, 150.0, 120.0)
  t.run_for(scrollbar_fade_ms)
  let thumb = t.drawn_rects().filter(fn(r) { r.2 == scroll_bar_size && r.0 > 280.0 }).get(0)
  match thumb {
    Some((tx, ty, tw, th, _)) => {
      let p = (tx + tw / 2.0 + 2.0, ty + th / 2.0)
      t.move(p.0, p.1)
      t.run_for(scrollbar_fade_ms)
      let before = t.list_offset()
      steps(t, p, there)
      (said, t.list_offset() - before)
    }
    None => (["no thumb"], 0.0)
  }
}

///|
/// Pressed at the thumb and dragged down 40, 10 each drag_step_ms, let go.
fn yield_drag(t : Tester, p : (Double, Double), _there : @signals.Signal[Bool]) -> Unit raise {
  t.press_at(p.0, p.1)
  for i in 1..=4 {
    t.move(p.0, p.1 + 10.0 * i.to_double())
    t.run_for(drag_step_ms)
  }
  t.release(p.0, p.1 + 40.0)
  t.frame()
}

///|
test "yield_thumbs: a mouse's press at the list's thumb under the edge's strip, dragged: the list scrolled, the edge told nothing" {
  let (said, moved) = yield_run(yield_drag)
  assert_true(moved > 0.0 && said.length() == 0, msg="\{said} \{moved}")
}

///|
test "yield_thumbs: a button of the tree's over the edge where the thumb is: its, the list not scrolled, the edge told nothing" {
  let (said, moved) = yield_run(yield_drag, cover=true)
  assert_true(moved == 0.0 && said.length() > 0 && said.iter().all(fn(s) { s.has_prefix("button") }), msg="\{said} \{moved}")
}

///|
test "yield_thumbs: a finger at the thumb a mouse brought out: the edge's" {
  let (said, moved) = yield_run(fn(t, p, _) raise {
    let at = t.time() + 10.0
    t.advance(at - t.time())
    t.touch_raw(0, 1, p.0, p.1, at)
    t.touch_raw(1, 1, p.0, p.1 + 20.0, at + 20.0)
    t.touch_raw(2, 1, p.0, p.1 + 20.0, at + 40.0)
  })
  assert_true(moved == 0.0 && said.contains("edge press"), msg="\{said} \{moved}")
}

///|
test "yield_thumbs: the old view let go while its thumb is held: what follows, no frame between, scrolls nothing and is none of the edge's" {
  let (said, _) = yield_run(fn(t, p, there) raise {
    t.press_at(p.0, p.1)
    // (held by the old view: its thumb's press)
    assert_true(view_held.val is Some(Old(_, _)), msg="held by the old view")
    t.move(p.0, p.1 + 10.0)
    t.frame()
    let held_at = t.list_offset()
    // (let go of at this event, nothing drawn after it till the hand is done)
    view_tree().unwrap().event(t.time(), fn() { there.set(false) })
    // (as it is let go: its hold let go with it, before anything more of the hand: the rest of it nobody's)
    assert_true(view_held.val is Some(Nowhere), msg="the old view's hold let go as it went")
    t.touch(1, p.0, p.1 + 20.0)
    t.touch(1, p.0, p.1 + 40.0)
    t.touch(2, p.0, p.1 + 40.0)
    assert_true(view_held.val is None, msg="held by none")
    // (made again by its name: its list as it was left, nothing of what followed its going scrolled it)
    view_tree().unwrap().event(t.time(), fn() { there.set(true) })
    t.frame()
    assert_eq(t.list_offset(), held_at, msg="the list as its thumb was left")
  })
  assert_true(said.iter().all(fn(s) { !s.has_prefix("edge") }), msg="\{said}")
}

///|
test "yield_thumbs: the pointer still at the thumb under the edge's strip, the thumb wheeled away from it and back: the edge pointed at as the thumb leaves, not as it is there" {
  let seen : Array[Bool] = []
  let (said, _) = yield_run(fn(t, p, _) raise {
    let tree = view_tree().unwrap()
    seen.push(tree.pointed_now() == yield_edge.val)
    // (the list wheeled far on: the thumb gone down from under the pointer, which stays; as the frame that publishes it
    // ends, the edge pointed at)
    t.wheel(p.0, p.1, 1200.0)
    seen.push(tree.pointed_now() == yield_edge.val)
    // (wheeled back as far: the thumb under the pointer again, as that frame ends the thumb's)
    t.wheel(p.0, p.1, -1200.0)
    seen.push(tree.pointed_now() == yield_edge.val)
  })
  ignore(said)
  assert_eq(seen, [false, true, false], msg="pointed at the edge: at the thumb, with it gone, with it back")
}

///|
test "yield_thumbs: the pointer and the thumb still, the old view's box rounded so its corner cuts the thumb where the pointer is, then square again: the edge pointed at while cut, not else" {
  let round = @signals.signal(0.0, same=fn(a, b) { a == b })
  let seen : Array[Bool] = []
  let rects : Array[Array[(Double, Double, Double, Double)]] = []
  let (said, _) = yield_run(round~, fn(t, p, _) raise {
    let tree = view_tree().unwrap()
    let thumb = fn() {
      t.drawn_rects().filter(fn(r) { r.2 == scroll_bar_size && r.0 > 280.0 }).map(fn(r) { (r.0, r.1, r.2, r.3) })
    }
    seen.push(tree.pointed_now() == yield_edge.val)
    rects.push(thumb())
    // (its top right corner as round as the box's half: the pointer, near the box's top right, outside what it cuts)
    tree.event(t.time(), fn() { round.set(150.0) })
    t.frame()
    seen.push(tree.pointed_now() == yield_edge.val)
    rects.push(thumb())
    tree.event(t.time(), fn() { round.set(0.0) })
    t.frame()
    seen.push(tree.pointed_now() == yield_edge.val)
    rects.push(thumb())
  })
  ignore(said)
  // (the thumb where it was, drawn as it was, all along: only its corner's cut changed)
  assert_true(rects.length() == 3 && rects[0].length() == 1 && rects.iter().all(fn(r) { r == rects[0] }), msg="the thumb: \{rects}")
  assert_eq(seen, [false, true, false], msg="pointed at the edge: at the thumb, cut, square again")
}

///|
// kept across runs: said again as each run makes its edge
/// The edge of the run under way (yield_run), as it is made.
let yield_edge : Ref[@view.NodeId?] = Ref(None)
