// What comes or goes down one column at one moment goes one way with what was on its way there then (flex's
// ComeGroup; the user 2026-11-03: what is left of the ways under way put with the new one, one whole going to where it
// all ends; 2026-11-09: 处理中 and the answer change places in one move): each its share, all of it setting out, turning
// and coming to where it goes together, so what is under them goes one way, or turns once, slowing first.

///|
/// The word drawn `w`'s top and height, as the tree is drawn now; none: (-1, 0).
fn cg_drawn(t : @view.Tree, w : String) -> (Double, Double) {
  match t.drawn().filter(fn(d) { d.words == w }) {
    [d, ..] => (d.y, d.h)
    _ => (-1.0, 0.0)
  }
}

///|
/// A column of rows by `keys` (each as tall as `tall` says), 下 under them; 处理中 comes at 100, and at the `swap`th
/// frame of 60 a second from then the rows are `then`. 下's top at each frame to 800, and when each row came to rest.
fn cg_rows(swap : Int, then : Array[String], frames? : Double = 1000.0 / 60.0) -> (Array[Double], Map[String, Double]) {
  let keys = @signals.signal(["头"], same=fn(a, b) { a == b })
  let tall : Map[String, Double] = { "头": 20.0, "处理中": 44.0, "回复": 71.1, "另": 30.0 }
  let t = @view.Tree::new(fn(root) {
    root.each(fn() { keys.get() }, fn(k) { k }, fn(row, k) {
      row.height(Is(Some(tall[k.get()]))).words(Is(k.get())) |> ignore
    })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { keys.set(["头", "处理中"]) })
  let ys = []
  let rest : Map[String, Double] = Map([])
  let last : Map[String, Double] = Map([])
  let mut i = 0
  let mut at = 100.0
  let mut swapped = false
  while at <= 800.0 {
    // (at the `swap`th frame of 60 a second, whatever frames are drawn)
    if !swapped && at >= 100.0 + swap.to_double() * 1000.0 / 60.0 - 0.001 {
      swapped = true
      t.event(at, fn() { keys.set(then) })
    }
    t.at(at)
    t.frame(390.0, 844.0) |> ignore
    ys.push(cg_drawn(t, "下").0)
    for w in ["处理中", "回复", "另"] {
      let h = cg_drawn(t, w).1
      if last.get(w) != Some(h) {
        rest[w] = at
        last[w] = h
      }
    }
    i = i + 1
    at = 100.0 + i.to_double() * frames
  }
  (ys, rest)
}

///|
/// How many times `ys` turns back (by more than a hundredth of a point), and the most it goes in a frame more than the
/// frame before (a step in its speed).
fn cg_turns(ys : Array[Double]) -> (Int, Double) {
  let mut turns = 0
  let mut dir = 0
  let mut most = 0.0
  for i in 1..<ys.length() {
    let d = ys[i] - ys[i - 1]
    if i >= 2 {
      most = cg_max(most, (d - (ys[i - 1] - ys[i - 2])).abs())
    }
    let s = if d > 0.01 { 1 } else if d < -0.01 { -1 } else { 0 }
    if s != 0 && dir != 0 && s != dir {
      turns = turns + 1
    }
    if s != 0 {
      dir = s
    }
  }
  (turns, most)
}

///|
fn cg_max(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
test "a row coming called back as another comes at once: what is under them one way, both there together" {
  // (early: 处理中 a frame on its way; late: all but there)
  for swap in [1, 11] {
    let (ys, rest) = cg_rows(swap, ["头", "回复"])
    let (turns, _) = cg_turns(ys)
    assert_eq(turns, 0, msg="swap at \{swap}: \{Repr(ys)}")
    assert_eq(ys[ys.length() - 1], 91.1)
    assert_eq(rest["处理中"], rest["回复"], msg="\{Repr(rest)}")
  }
}

///|
test "a row coming called back as another comes, the whole turned back: it slows as one, then turns once" {
  // (处理中 called back a third and most of the way open, 另 (30, less than it) coming in its place: all of it turned)
  for swap in [3, 10] {
    let (ys, rest) = cg_rows(swap, ["头", "另"])
    let (turns, _) = cg_turns(ys)
    assert_true(turns <= 1, msg="swap at \{swap}: \{Repr(ys)}")
    assert_eq(ys[ys.length() - 1], 50.0)
    assert_eq(rest["处理中"], rest["另"], msg="\{Repr(rest)}")
  }
}

///|
test "a group's way the same whether frames were drawn between its cause and after or not" {
  let at_every = fn(frames : Double) {
    let (ys, _) = cg_rows(4, ["头", "回复"], frames~)
    ys
  }
  let a = at_every(1000.0 / 60.0)
  let b = at_every(1000.0 / 120.0)
  // (the same moments of each: every 60th of a second)
  for i in 0..<a.length() {
    assert_eq(a[i], b[i * 2], msg="at \{i}")
  }
}

///|
test "a show closing and another opening down a column at once with one between, nothing tall too: under them one way" {
  for between in [40.0, 0.0] {
    let a_on = @signals.signal(true, same=fn(a, b) { a == b })
    let c_on = @signals.signal(false, same=fn(a, b) { a == b })
    let t = @view.Tree::new(fn(root) {
      root.show(fn() { a_on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("A")) |> ignore })
      root.box(fn(b) { b.height(Is(Some(between))).words(Is("B")) |> ignore }) |> ignore
      root.show(fn() { c_on.get() }, fn(v) { v.height(Is(Some(60.0))).words(Is("C")) |> ignore })
      root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    t.event(100.0, fn() {
      a_on.set(false)
      c_on.set(true)
    })
    let ys = []
    let mut i = 0
    while i <= 40 {
      t.at(100.0 + i.to_double() * 1000.0 / 120.0)
      t.frame(390.0, 844.0) |> ignore
      ys.push(cg_drawn(t, "下").0)
      i = i + 1
    }
    let (turns, _) = cg_turns(ys)
    assert_eq(turns, 0, msg="\{between}: \{Repr(ys)}")
    assert_eq(ys[ys.length() - 1], between + 60.0)
  }
}

///|
test "a group said as what one in it holds is on its way too: the same at each moment whatever frames are drawn" {
  // (回复's own 里 opening 30 ms before it comes in 处理中's place: what it comes to measured at that moment)
  let at_every = fn(frames : Double) -> Array[Double] {
    let keys = @signals.signal(["头"], same=fn(a, b) { a == b })
    let inner = @signals.signal(false, same=fn(a, b) { a == b })
    let t = @view.Tree::new(fn(root) {
      root.each(fn() { keys.get() }, fn(k) { k }, fn(row, k) {
        if k.get() == "回复" {
          row.box(fn(b) { b.height(Is(Some(40.0))).words(Is("回复")) |> ignore }) |> ignore
          row.show(fn() { inner.get() }, fn(v) { v.height(Is(Some(30.0))).words(Is("里")) |> ignore })
        } else {
          row.height(Is(Some(if k.get() == "头" { 20.0 } else { 44.0 }))).words(Is(k.get())) |> ignore
        }
      })
      root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    t.event(100.0, fn() { keys.set(["头", "处理中", "回复"]) })
    let ms = Ref(100.0)
    let out = []
    let step_to = fn(to : Double) {
      if frames > 0.0 {
        while ms.val + frames < to {
          ms.val = ms.val + frames
          t.at(ms.val)
          t.frame(390.0, 844.0) |> ignore
        }
      }
      ms.val = to
      t.at(to)
      t.frame(390.0, 844.0) |> ignore
      out.push(cg_drawn(t, "下").0)
    }
    step_to(170.0)
    t.event(170.0, fn() { inner.set(true) })
    step_to(200.0)
    t.event(200.0, fn() { keys.set(["头", "回复"]) })
    for at in [220.0, 260.0, 320.0, 400.0, 900.0] {
      step_to(at)
    }
    out
  }
  let jumped = at_every(0.0)
  for frames in [1000.0 / 60.0, 1000.0 / 120.0, 1000.0 / 24.0, 1000.0 / 7.0] {
    assert_eq(at_every(frames), jumped, msg="\{frames}")
  }
}

///|
/// A column of A (40 tall) and C (60) shown as `a0` and `c0` say from the first, 20 between them and 下 under them;
/// at each of `events`' moments A's and C's shows set as it says (none: left). A's and C's heights and 下's top at each
/// frame `step` apart from `from` to `to`; `inner`: at that moment a show 30 tall opens in a box of its own beside.
fn cg_two(
  a0 : Bool,
  c0 : Bool,
  events : Array[(Double, Bool?, Bool?)],
  from : Double,
  to : Double,
  step? : Double = 1000.0 / 60.0,
  inner? : Double,
) -> Array[(Double, Double, Double)] {
  let a_on = @signals.signal(a0, same=fn(a, b) { a == b })
  let c_on = @signals.signal(c0, same=fn(a, b) { a == b })
  let i_on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { a_on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("A")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("B")) |> ignore }) |> ignore
    root.show(fn() { c_on.get() }, fn(v) { v.height(Is(Some(60.0))).words(Is("C")) |> ignore })
    root.box(fn(b) {
      b.show(fn() { i_on.get() }, fn(v) { v.height(Is(Some(30.0))).words(Is("I")) |> ignore }) |> ignore
    })
    |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  let due = events.copy()
  match inner {
    Some(at) => due.push((at, None, None))
    None => ()
  }
  due.sort_by_key(fn(e) { e.0 })
  let out = []
  let mut at = 0.0
  let mut i = 0
  let mut f = 0
  while at <= to {
    while i < due.length() && due[i].0 <= at + 0.001 {
      let (when, a, c) = due[i]
      t.event(when, fn() {
        if a is Some(x) {
          a_on.set(x)
        }
        if c is Some(x) {
          c_on.set(x)
        }
        if a is None && c is None {
          i_on.set(true)
        }
      })
      i = i + 1
    }
    t.at(at)
    t.frame(390.0, 844.0) |> ignore
    if at >= from - 0.001 {
      out.push((cg_drawn(t, "A").1, cg_drawn(t, "C").1, cg_drawn(t, "下").0))
    }
    // (each frame's moment as a multiple of the step, not a sum: the same moments at 60 and 120 a second, bit for bit)
    f = f + 1
    at = f.to_double() * step
  }
  out
}

///|
test "one that went in a group, then set off alone: its way bit for bit as one that never went in one" {
  let s = 1000.0 / 60.0
  // (A opening again alone, then C closing alone, once both are at rest)
  for again in [(Some(true), None), (None, Some(false))] {
    let (a, c) = again
    let grouped = cg_two(true, false, [(100.0, Some(false), Some(true)), (90.0 * s, a, c)], 90.0 * s, 140.0 * s)
    let alone = cg_two(true, false, [(100.0, Some(false), None), (40.0 * s, None, Some(true)), (90.0 * s, a, c)], 90.0 * s, 140.0 * s)
    assert_eq(grouped, alone, msg="\{Repr(again)}")
  }
}

///|
test "both of a group set off again together once at rest: bit for bit as the same change made from rest" {
  let s = 1000.0 / 60.0
  let again = cg_two(true, false, [(100.0, Some(false), Some(true)), (90.0 * s, Some(true), Some(false))], 90.0 * s, 140.0 * s)
  let fresh = cg_two(false, true, [(90.0 * s, Some(true), Some(false))], 90.0 * s, 140.0 * s)
  assert_eq(again, fresh)
  let ys = again.map(fn(r) { r.2 })
  let (turns, _) = cg_turns(ys)
  assert_eq(turns, 0, msg="\{Repr(ys)}")
}

///|
test "one of a group turned back on its way, the other on its way: a group of the two again, the same whatever frames" {
  let run = fn(step : Double) {
    cg_two(true, false, [(100.0, Some(false), Some(true)), (150.0, Some(true), None)], 0.0, 1000.0, step~)
  }
  let a = run(1000.0 / 60.0)
  let b = run(1000.0 / 120.0)
  for i in 0..<a.length() {
    assert_eq(a[i], b[i * 2], msg="at \{i}: \{Repr(a[i])} \{Repr(b[i * 2])}")
  }
  let (turns, _) = cg_turns(a.map(fn(r) { r.2 }))
  assert_true(turns <= 1, msg="\{Repr(a)}")
  assert_eq(a[a.length() - 1], (40.0, 60.0, 120.0))
}

///|
test "what is on its way down a column, a show opening in another at that moment: its way untouched, bit for bit" {
  let opened = cg_two(true, false, [(100.0, Some(false), None)], 0.0, 800.0, inner=150.0)
  let without = cg_two(true, false, [(100.0, Some(false), None)], 0.0, 800.0)
  assert_eq(opened.map(fn(r) { r.0 }), without.map(fn(r) { r.0 }))
}

///|
test "rows as tall as each other coming at one moment: each as it comes alone, to a millionth of a point" {
  let keys = @signals.signal(["头"], same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.each(fn() { keys.get() }, fn(k) { k }, fn(row, k) {
      row.height(Is(Some(if k.get() == "头" { 20.0 } else { 44.0 }))).words(Is(k.get())) |> ignore
    })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { keys.set(["头", "甲", "乙", "丙"]) })
  let mut f = 0
  let mut at = 100.0
  // (to well past where a Move as far as 44 is over)
  while at <= 100.0 + @flex.move_ms(44.0) * 2.0 {
    t.at(at)
    t.frame(390.0, 844.0) |> ignore
    let alone = @flex.come_way(0.0, 0.0, 44.0, at - 100.0).0
    for w in ["甲", "乙", "丙"] {
      assert_true((cg_drawn(t, w).1 - alone).abs() < 1.0e-6, msg="\{w} at \{at}: \{cg_drawn(t, w).1} \{alone}")
    }
    f = f + 1
    at = 100.0 + f.to_double() * 1000.0 / 60.0
  }
}

///|
test "a show opening down a column at the moment another opens laid out nowhere (its room shut): the one laid out goes its own way, as alone, from nothing to its height, never none on the way, the same at every rate" {
  // (the one laid out nowhere is never measured, how tall it goes to never known: said with it, the group's way was
  // worked out of a height that is no number, each in it laid out none all the way and whole at its end
  // (Tree::come_group_settle, after its wait for the layout under way))
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let want = looks.map(fn(at) { @flex.come_way(0.0, 0.0, 60.0, at - rc_at).0 })
  for rate in rc_rates {
    let on = @signals.signal(false)
    let t = @view.Tree::new(fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(300.0))) |> ignore
        col.show(fn() { on.get() }, fn(s) { s.height(Is(Some(60.0))) |> ignore })
        col.show(fn() { on.get() }, fn(s) { s.laid_nowhere(Is(true)).height(Is(Some(40.0))) |> ignore })
        col.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
      })
      |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    let under = rc_y(t, "下")
    let got = rc_walk(t, [(rc_at, fn() { on.set(true) })], looks, rate, fn() { rc_y(t, "下") - under })
    assert_true(rc_near(got, want), msg="at \{rate} a second: \{Repr(got)} for \{Repr(want)}")
  }
}
