// A key its page says comes whole (View::scrolls_window's `comes_whole`: the viewer's own words sent, the coordinator of
// the migration, 2026-11-14), coming by data at the foot of a list that follows it: its block makes its way as any key's
// (where everything is at every look, the same as an unmarked key's run), but what it holds is drawn as at rest all
// the way: at full ink and its size, from the block's top, cut by nothing of its room (only by where the list shows),
// and the paint is told to draw it over the rest of its list (Tree::raised_blocks; the order itself is the paint's, held
// in ui's list_key_whole_wbtest). Where there is room that holds it, it is there at once as any key; not at its foot,
// `at_once` or with motion reduced, it is as an unmarked key, and nothing is raised. Looked at every 10 ms, in one jump
// and at 60, 120, 24 and 7 a second (rc_walk).

///|
/// The moment the key comes, and how long after it is looked at.
let wk_at : Double = 500.5

///|
let wk_after_ms : Double = 700.0

///|
/// How tall the key (72) is: its words a line of 24 at its top, the rest under them.
let wk_tall : Double = 64.0

///|
/// The list's pinned foot.
let wk_foot : Double = 30.0

///|
/// A page's list 300 by 400 of rows 0 to 9 (40 each, words 行k), following its foot, a pinned foot wk_foot tall; key
/// 72 said to come whole where `marked`; under them a line (50, 44 tall, said to leave its room) where `under` (the key
/// coming over it) or, `room`, there and gone before so that its room holds a key of 40 (73). Drawn once, at 0.
fn wk_case(
  marked : Bool,
  under? : Bool = false,
  room? : Bool = false,
  at_once? : Bool = false,
  reduced? : Bool = false,
) -> (@view.Tree, @signals.Signal[Array[Int]], @view.Scroll) {
  let first = Array::makei(10, fn(i) { i })
  if under {
    first.push(50)
  }
  let keys = @signals.signal(first, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { true },
        leaves_room=fn(k) { k == 50 && room },
        comes_whole=fn(k) { marked && (k == 72 || k == 73) },
        at_once~,
        foot=fn(f) { f.box(fn(b) { b.height(Is(Some(wk_foot))).shrink(Is(0.0)) |> ignore }) |> ignore },
        fn(b, k) {
          if k == 72 {
            b.box(fn(w) { w.height(Is(Some(24.0))).shrink(Is(0.0)).words(Is("行72")) |> ignore }) |> ignore
            b.box(fn(r) { r.height(Is(Some(wk_tall - 24.0))).shrink(Is(0.0)) |> ignore }) |> ignore
          } else if k == 73 {
            b.box(fn(w) { w.height(Is(Some(24.0))).shrink(Is(0.0)).words(Is("行73")) |> ignore }) |> ignore
            b.box(fn(r) { r.height(Is(Some(16.0))).shrink(Is(0.0)) |> ignore }) |> ignore
          } else if k == 50 {
            b.height(Is(Some(44.0))).words(Is("线")) |> ignore
          } else {
            b.height(Is(Some(40.0))).words(Is("行\{k}")) |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  if reduced {
    tree.reduces_motion(fn() { true })
  }
  tree.frame(390.0, 844.0) |> ignore
  (tree, keys, scroll)
}

///|
/// What one look sees: where 行9 is, the key's words as drawn (top, height, width, opacity; rc_none's top where they
/// are not), whether they are drawn cut by anything but where the list shows, and how many blocks are raised.
priv struct WkLook {
  y9 : Double
  wy : Double
  wh : Double
  ww : Double
  wa : Double
  cut : String?
  raised : Int
}

///|
/// The key's words `w` as drawn in `t`, and what cuts them other than the list's own box (300 by 400 at the top left).
fn wk_read(t : @view.Tree, w : String) -> WkLook {
  let held = t.drawn_held()
  let mut look : WkLook = {
    y9: rc_y(t, "行9"),
    wy: rc_none,
    wh: 0.0,
    ww: 0.0,
    wa: 0.0,
    cut: None,
    raised: t.raised_blocks().length(),
  }
  for i, e in held {
    let (d, _, _) = e
    guard d.words == w else { continue }
    let mut lo = 0.0
    let mut hi = 400.0
    let mut h = held[i].1
    while h >= 0 {
      let (c, up, _) = held[h]
      if c.clips {
        lo = if c.y > lo { c.y } else { lo }
        hi = if c.y + c.h < hi { c.y + c.h } else { hi }
      }
      h = up
    }
    let foot = if d.y + d.h < 400.0 { d.y + d.h } else { 400.0 }
    let cut = if d.alpha > 0.0 && (lo > d.y + 0.01 || hi < foot - 0.01) {
      Some("\{w} drawn \{d.y}..\{d.y + d.h}, cut to \{lo}..\{hi}")
    } else {
      None
    }
    look = { ..look, wy: d.y, wh: d.h, ww: d.w, wa: d.alpha, cut }
    break
  }
  look
}

///|
/// The case walked from before the key comes to its rest at `rate`, `events` before it (each a moment and what changes)
/// and the key (`k`) at wk_at; `up` read up before it (0: at its foot).
fn wk_walk(
  c : (@view.Tree, @signals.Signal[Array[Int]], @view.Scroll),
  rate : Double,
  k? : Int = 72,
  before? : Array[(Double, () -> Unit)] = [],
  up? : Double = 0.0,
) -> Array[WkLook] {
  let (tree, keys, _) = c
  let events = before.copy()
  events.push((wk_at, fn() {
    let now = keys.untracked().copy()
    // (over the line where it stays: in its place before it)
    match now.search(50) {
      Some(i) => now.insert(i, k)
      None => now.push(k)
    }
    keys.set(now)
  }))
  if up > 0.0 {
    rc_walk(tree, before, [wk_at - 300.0], rate, fn() { () }) |> ignore
    tree.wheel_at(150.0, 100.0, 0.0, -up, 0, wk_at - 290.0) |> ignore
  }
  let from = if up > 0.0 { wk_at - 290.0 } else { 0.0 }
  let looks = []
  let mut at = wk_at - 10.0
  while at <= wk_at + wk_after_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  rc_walk(tree, events.filter(fn(e) { e.0 >= from }), looks, rate, from~, fn() { wk_read(tree, "行\{k}") })
}

///|
test "a key said to come whole at the foot: its words at full ink and their size from the block's top at every look, cut by nothing of its room, raised while on its way; what is over it where an unmarked key's run has it, at every look and rate" {
  for rate in rc_rates {
    let at = "at \{rate} a second"
    let marked = wk_walk(wk_case(true), rate)
    let plain = wk_walk(wk_case(false), rate)
    assert_eq(marked.length(), plain.length())
    let rest = marked[marked.length() - 1]
    let mut on_way = 0
    let mut faded = 0
    for i, m in marked {
      let p = plain[i]
      assert_true((m.y9 - p.y9).abs() < 0.01, msg="\{at}, look \{i}: 行9 at \{m.y9}, \{p.y9} as an unmarked key's")
      if p.wy != rc_none && p.wa < 0.999 {
        faded += 1
      }
      guard i > 0 else {
        assert_eq(m.raised, 0, msg="\{at}: raised before it came")
        continue
      }
      // (drawn from the change's look on, at rest: its size, full ink, against 行9's foot)
      assert_true(m.wy != rc_none, msg="\{at}, look \{i}: the key's words not drawn")
      assert_true((m.wa - 1.0).abs() < 0.001, msg="\{at}, look \{i}: drawn at \{m.wa}")
      assert_true((m.wh - 24.0).abs() < 0.01 && (m.ww - rest.ww).abs() < 0.01, msg="\{at}, look \{i}: drawn \{m.ww}×\{m.wh}")
      assert_true((m.wy - (m.y9 + 40.0)).abs() < 0.5, msg="\{at}, look \{i}: its words at \{m.wy}, 行9's foot at \{m.y9 + 40.0}")
      match m.cut {
        Some(w) => fail("\{at}, look \{i}: \{w}")
        None => ()
      }
      if m.raised > 0 {
        on_way += 1
      }
    }
    assert_true(on_way > 0 || rate == 0.0, msg="\{at}: never raised on its way")
    assert_eq(rest.raised, 0, msg="\{at}: raised at rest")
    assert_true(faded > 0, msg="\{at}: the unmarked key never drawn faded: the case shows nothing")
    // (at rest as an unmarked key)
    let prest = plain[plain.length() - 1]
    assert_true((rest.wy - prest.wy).abs() < 0.01 && (rest.wa - prest.wa).abs() < 0.001, msg="\{at}: at rest otherwise")
  }
}

///|
test "a key said to come whole over a line that stays under it: drawn whole, raised (over the line too: the paint's), what is over it as an unmarked key's run" {
  for rate in [0.0, 60.0, 120.0] {
    let at = "at \{rate} a second"
    let marked = wk_walk(wk_case(true, under=true), rate)
    let plain = wk_walk(wk_case(false, under=true), rate)
    let mut raised = 0
    for i, m in marked {
      assert_true((m.y9 - plain[i].y9).abs() < 0.01, msg="\{at}, look \{i}: 行9 at \{m.y9}, \{plain[i].y9} unmarked")
      if i > 0 {
        assert_true((m.wa - 1.0).abs() < 0.001 && (m.wh - 24.0).abs() < 0.01, msg="\{at}, look \{i}: drawn \{m.wh} at \{m.wa}")
        match m.cut {
          Some(w) => fail("\{at}, look \{i}: \{w}")
          None => ()
        }
      }
      raised += m.raised
    }
    assert_true(raised > 0 || rate == 0.0, msg="\{at}: never raised")
  }
}

///|
test "a key said to come whole into room that holds it: there at once, whole, as an unmarked key, nothing raised" {
  for rate in [0.0, 60.0, 120.0] {
    let at = "at \{rate} a second"
    let walk = fn(marked : Bool) {
      let c = wk_case(marked, room=true)
      let (_, keys, _) = c
      let ev : Array[(Double, () -> Unit)] = []
      ev.push((100.5, fn() {
        let ks = Array::makei(10, fn(i) { i })
        ks.push(50)
        keys.set(ks)
      }))
      ev.push((300.5, fn() { keys.set(Array::makei(10, fn(i) { i })) }))
      wk_walk(c, rate, k=73, before=ev)
    }
    let marked = walk(true)
    let plain = walk(false)
    for i, m in marked {
      let p = plain[i]
      assert_true((m.y9 - p.y9).abs() < 0.01 && (m.wy - p.wy).abs() < 0.01, msg="\{at}, look \{i}: otherwise than unmarked")
      if i > 0 {
        assert_true((m.wa - 1.0).abs() < 0.001, msg="\{at}, look \{i}: drawn at \{m.wa}")
      }
      assert_eq(m.raised, 0, msg="\{at}, look \{i}: raised")
    }
  }
}

///|
test "a key said to come whole, not at the foot, said at once, or with motion reduced: as an unmarked key, nothing raised" {
  for rate in [0.0, 60.0] {
    let cases : Array[(String, (Bool) -> Array[WkLook])] = [
      ("read up", fn(m) { wk_walk(wk_case(m), rate, up=60.0) }),
      ("at once", fn(m) { wk_walk(wk_case(m, at_once=true), rate) }),
      ("reduced", fn(m) { wk_walk(wk_case(m, reduced=true), rate) }),
    ]
    for c in cases {
      let at = "\{c.0}, at \{rate} a second"
      let marked = (c.1)(true)
      let plain = (c.1)(false)
      for i, m in marked {
        let p = plain[i]
        assert_true(
          (m.y9 - p.y9).abs() < 0.01 && (m.wy - p.wy).abs() < 0.01 && (m.wa - p.wa).abs() < 0.001 && (m.wh - p.wh).abs() < 0.01,
          msg="\{at}, look \{i}: \{Repr((m.y9, m.wy, m.wa, m.wh))}, unmarked \{Repr((p.y9, p.wy, p.wa, p.wh))}",
        )
        assert_eq(m.raised, 0, msg="\{at}, look \{i}: raised")
      }
    }
  }
}

///|
test "two keys said to come whole, put over a line that stays under them 100 ms apart, the first still on its way as the second comes: both raised while both go, each drawn whole at full ink at every look" {
  for rate in [0.0, 60.0, 120.0, 24.0, 7.0] {
    let at = "at \{rate} a second"
    let (tree, keys, _) = wk_case(true, under=true)
    let events : Array[(Double, () -> Unit)] = [
      (wk_at, fn() { keys.set(Array::makei(10, fn(i) { i }) + [72, 50]) }),
      (wk_at + 100.0, fn() { keys.set(Array::makei(10, fn(i) { i }) + [72, 73, 50]) }),
    ]
    let looks = []
    let mut t = wk_at + 110.0
    while t <= wk_at + wk_after_ms {
      looks.push(t)
      t = t + rc_look_ms
    }
    let seen = rc_walk(tree, events, looks, rate, fn() { (wk_read(tree, "行72"), wk_read(tree, "行73")) })
    let mut both = 0
    for i, s in seen {
      let (a, b) = s
      for w in [a, b] {
        assert_true(w.wy != rc_none && (w.wa - 1.0).abs() < 0.001 && (w.wh - 24.0).abs() < 0.01, msg="\{at}, look \{i}: drawn \{w.wh} at \{w.wa}")
        match w.cut {
          Some(c) => fail("\{at}, look \{i}: \{c}")
          None => ()
        }
      }
      if a.raised == 2 {
        both += 1
      }
    }
    assert_true(both > 0 || rate == 0.0, msg="\{at}: never both raised")
    assert_eq(seen[seen.length() - 1].0.raised, 0, msg="\{at}: raised at rest")
  }
}
