// A pick said to leave over a time (pick_leave.mbt) whose place's way would go with another's in its column (said in
// the same change, or under way then): its place holds as big as it was till what fades over it is gone, setting out
// then in the one way of what still goes there; and what fades is drawn whole where it was, across as down, its place
// at least as big across as it was laid till it is gone; one whose side makes nothing laid out nowhere at rest. Never
// both seen.

///|
/// Where the clip round words `w` (all that holds them cutting what it holds) cuts them now, across or down: none, or
/// what (none too where they are not seen).
fn plg_cut(t : @view.Tree, w : String) -> String? {
  let held = t.drawn_held()
  for i, e in held {
    let (d, _, _) = e
    guard d.words == w && d.alpha > 0.0 else { continue }
    let mut l = @double.neg_infinity
    let mut r = @double.infinity
    let mut top = @double.neg_infinity
    let mut foot = @double.infinity
    let mut k = held[i].1
    while k >= 0 {
      let (c, up, _) = held[k]
      if c.clips {
        l = if c.x > l { c.x } else { l }
        r = if c.x + c.w < r { c.x + c.w } else { r }
        top = if c.y > top { c.y } else { top }
        foot = if c.y + c.h < foot { c.y + c.h } else { foot }
      }
      k = up
    }
    if l > d.x + 0.01 || r < d.x + d.w - 0.01 || top > d.y + 0.01 || foot < d.y + d.h - 0.01 {
      return Some("\{w} drawn at \{d.x},\{d.y} \{d.w}x\{d.h} (alpha \{d.alpha}), its clip \{l}..\{r} across, \{top}..\{foot} down")
    }
  }
  None
}

///|
/// Where words `w` are drawn now (x, y), none where they are not.
fn plg_at(t : @view.Tree, w : String) -> (Double, Double)? {
  t.drawn().iter().find_first(fn(d) { d.words == w }).map(fn(d) { (d.x, d.y) })
}

///|
/// A column: a pick leaving over pick_leave_ms (`tall`: 高, 60 tall; else 矮, 40 tall, or nothing where `to_nothing`),
/// 中 (10) under it, a show of 显 (30) while `other`, 下 (20).
fn plg_column(tall : @signals.Signal[Bool], other : @signals.Signal[Bool], to_nothing : Bool) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.pick(leave=pick_leave_ms, fn() { tall.get() }, fn(v, k) {
      if k {
        v.height(Is(Some(60.0))).words(Is("高")) |> ignore
      } else if !to_nothing {
        v.height(Is(Some(40.0))).words(Is("矮")) |> ignore
      }
    })
    root.box(fn(b) { b.height(Is(Some(10.0))).words(Is("中")) |> ignore }) |> ignore
    root.show(fn() { other.get() }, fn(v) { v.height(Is(Some(30.0))).words(Is("显")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
}

///|
/// The pick's place's height now: where 中 is (the place at the column's top).
fn plg_place(t : @view.Tree) -> Double {
  match plg_at(t, "中") {
    Some((_, y)) => y
    None => -1.0
  }
}

///|
/// From the change at `at` (高 for the shorter, `other` set to `other_to` in the same change, or at `other_at` before)
/// a frame each ms to `to`: the place as tall as it was and 高 drawn whole till `at` + pick_leave_ms, 矮 not seen;
/// the place closing after; never both seen. `say` names the case.
fn plg_hold(to_nothing : Bool, other_from : Bool, other_at : Double, say : String) -> Unit raise {
  let tall = @signals.signal(true, same=fn(a, b) { a == b })
  let other = @signals.signal(other_from, same=fn(a, b) { a == b })
  let t = plg_column(tall, other, to_nothing)
  t.frame(390.0, 844.0) |> ignore
  let at = 100.0
  if other_at < at {
    t.event(other_at, fn() { other.set(!other_from) })
  }
  t.event(at, fn() {
    tall.set(false)
    if other_at == at {
      other.set(!other_from)
    }
  })
  let gone = at + pick_leave_ms
  let mut closed = false
  let mut m = at
  while m <= gone + 600.0 {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    let high = pick_leave_alpha(t, "高")
    let short = pick_leave_alpha(t, "矮")
    let place = plg_place(t)
    assert_false(high > 0.0 && short > 0.0, msg="\{say}: both seen at \{m}: \{high}, \{short}")
    if m <= gone {
      assert_true((place - 60.0).abs() <= 0.01, msg="\{say}: the place \{place} tall at \{m}, before 高 was gone")
      assert_eq(short, 0.0, msg="\{say}: 矮 seen at \{m}, before 高 was gone")
      match plg_cut(t, "高") {
        Some(w) => fail("\{say}, at \{m}: \{w}")
        None => ()
      }
    } else if place < 59.99 {
      closed = true
    }
    m = m + 1.0
  }
  assert_true(closed, msg="\{say}: the place never closed after 高 was gone")
  let rest = if to_nothing { 0.0 } else { 40.0 }
  assert_true((plg_place(t) - rest).abs() <= 0.01, msg="\{say}: the place \{plg_place(t)} at rest, not \{rest}")
  assert_false(t.clock_read())
}

///|
test "a pick leaving over a time for a shorter one, or for nothing, down a column, in the change by which another way is said there: its place as tall as it was till what fades is gone, that drawn whole, never both seen" {
  for to_nothing in [false, true] {
    // (a show coming under it, and one going)
    plg_hold(to_nothing, false, 100.0, "to nothing \{to_nothing}, a show coming")
    plg_hold(to_nothing, true, 100.0, "to nothing \{to_nothing}, a show going")
  }
}

///|
test "a pick leaving over a time for a shorter one, or for nothing, down a column, another way there under way as it changes: its place as tall as it was till what fades is gone, that drawn whole, never both seen" {
  for to_nothing in [false, true] {
    plg_hold(to_nothing, false, 50.0, "to nothing \{to_nothing}, a show coming from 50")
    plg_hold(to_nothing, true, 50.0, "to nothing \{to_nothing}, a show going from 50")
  }
}

///|
test "a pick leaving over a time, its place set out once what fades is gone, another way still going in its column then: the two one way, at rest at the same moment" {
  // (the other said with the pick's change, and said while the place waits: each still going as the place sets out)
  for other_at in [100.0, 250.0] {
    let tall = @signals.signal(true, same=fn(a, b) { a == b })
    let other = @signals.signal(false, same=fn(a, b) { a == b })
    let t = plg_column(tall, other, false)
    t.frame(390.0, 844.0) |> ignore
    t.event(100.0, fn() {
      tall.set(false)
      if other_at == 100.0 {
        other.set(true)
      }
    })
    if other_at > 100.0 {
      t.at(other_at)
      t.frame(390.0, 844.0) |> ignore
      t.event(other_at, fn() { other.set(true) })
    }
    let from = if other_at > 100.0 { other_at } else { 100.0 }
    // (the last frame each changed at all: the place's height (where 中 is) and the show's; a share of one way all but
    // there changes by little, not by nothing)
    let mut place_last = -1.0
    let mut show_last = -1.0
    let mut place_was = plg_place(t)
    let mut show_was = -1.0
    let mut sets_out = -1.0
    let mut m = from
    while m <= 1500.0 {
      t.at(m)
      t.frame(390.0, 844.0) |> ignore
      let place = plg_place(t)
      let show = match t.drawn().iter().find_first(fn(d) { d.words == "显" }) {
        Some(d) => d.h
        None => -1.0
      }
      if place != place_was {
        place_last = m
        if sets_out < 0.0 {
          sets_out = m
        }
      }
      if show_was >= 0.0 && show != show_was {
        show_last = m
      }
      place_was = place
      show_was = show
      m = m + 1.0
    }
    let say = "the other said at \{other_at}"
    assert_true(sets_out > 100.0 + pick_leave_ms, msg="\{say}: the place set out at \{sets_out}, before 高 was gone")
    assert_true(show_last > sets_out, msg="\{say}: the show at rest at \{show_last}, before the place set out at \{sets_out}")
    assert_eq(place_last, show_last, msg="\{say}: the place at rest at \{place_last}, the show at \{show_last}")
    assert_true((plg_place(t) - 40.0).abs() <= 0.01, msg="\{say}: the place \{plg_place(t)} at rest")
    assert_false(t.clock_read())
  }
}

///|
test "a pick leaving over a time in a column that centres what it holds, for nothing or for a narrower one: what fades where it was across all the way, its clip as wide as it is" {
  for to_nothing in [true, false] {
    let wide = @signals.signal(true, same=fn(a, b) { a == b })
    let t = @view.Tree::new(fn(root) {
      root.box(fn(c) {
        c.lines_up(Is(Some(Middle))) |> ignore
        c.pick(leave=pick_leave_ms, fn() { wide.get() }, fn(v, k) {
          if k {
            v.width(Is(Some(120.0))).height(Is(Some(20.0))).words(Is("宽宽")) |> ignore
          } else if !to_nothing {
            v.width(Is(Some(40.0))).height(Is(Some(20.0))).words(Is("窄")) |> ignore
          }
        })
        c.box(fn(b) { b.width(Is(Some(60.0))).height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
      })
      |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    let say = "to nothing \{to_nothing}"
    guard plg_at(t, "宽宽") is Some((x0, _)) else { fail("\{say}: 宽宽 not drawn") }
    assert_true((x0 - (390.0 - 120.0) / 2.0).abs() <= 0.01, msg="\{say}: 宽宽 at \{x0}, not centred")
    t.event(100.0, fn() { wide.set(false) })
    let mut m = 100.0
    while m <= 100.0 + pick_leave_ms + 600.0 {
      t.at(m)
      t.frame(390.0, 844.0) |> ignore
      let wider = pick_leave_alpha(t, "宽宽")
      let narrow = pick_leave_alpha(t, "窄")
      assert_false(wider > 0.0 && narrow > 0.0, msg="\{say}: both seen at \{m}: \{wider}, \{narrow}")
      if wider > 0.0 {
        guard plg_at(t, "宽宽") is Some((x, _)) else { fail("\{say}: 宽宽 not drawn at \{m}") }
        assert_true((x - x0).abs() <= 0.01, msg="\{say}: 宽宽 at \{x} at \{m}, \{x0} before the change")
        match plg_cut(t, "宽宽") {
          Some(w) => fail("\{say}, at \{m}: \{w}")
          None => ()
        }
      }
      m = m + 1.0
    }
    assert_eq(pick_leave_alpha(t, "宽宽"), 0.0)
    if !to_nothing {
      assert_eq(pick_leave_alpha(t, "窄"), 1.0)
      guard plg_at(t, "窄") is Some((x, _)) else { fail("\{say}: 窄 not drawn at rest") }
      assert_true((x - (390.0 - 40.0) / 2.0).abs() <= 0.01, msg="\{say}: 窄 at \{x} at rest, not centred")
    }
    assert_false(t.clock_read())
  }
}

///|
test "a pick leaving over a time along a row, a taller one going for a shorter: what fades not cut across for its fade, never both seen" {
  let tall = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).height(Is(Some(20.0))).words(Is("左")) |> ignore }) |> ignore
      r.pick(along_row=true, leave=pick_leave_ms, fn() { tall.get() }, fn(v, k) {
        if k {
          v.width(Is(Some(60.0))).height(Is(Some(60.0))).words(Is("高高")) |> ignore
        } else {
          v.width(Is(Some(40.0))).height(Is(Some(30.0))).words(Is("矮")) |> ignore
        }
      })
      r.box(fn(b) { b.width(Is(Some(20.0))).height(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { tall.set(false) })
  let mut m = 100.0
  while m <= 100.0 + pick_leave_ms + 600.0 {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    let high = pick_leave_alpha(t, "高高")
    let short = pick_leave_alpha(t, "矮")
    assert_false(high > 0.0 && short > 0.0, msg="both seen at \{m}: \{high}, \{short}")
    match plg_cut(t, "高高") {
      Some(w) => fail("at \{m}: \{w}")
      None => ()
    }
    m = m + 1.0
  }
  assert_eq(pick_leave_alpha(t, "矮"), 1.0)
  assert_eq(t.drawn().filter(fn(d) { d.words == "右" })[0].x, 60.0)
  assert_false(t.clock_read())
}

///|
test "a pick leaving over a time whose side makes nothing, in a column with a gap: no gap of its own at rest, its gap opening and closing with its way, never at once" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(c) {
      c.gap(Is(4.0)) |> ignore
      c.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
      c.pick(leave=pick_leave_ms, fn() { on.get() }, fn(v, k) {
        if k {
          v.height(Is(Some(20.0))).words(Is("显")) |> ignore
        }
      })
      c.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  let under = fn() {
    match plg_at(t, "下") {
      Some((_, y)) => y
      None => -1.0
    }
  }
  assert_eq(under(), 24.0, msg="下 at \{under()} with nothing shown")
  for change in [(100.0, true, 48.0), (1000.0, false, 24.0)] {
    let (at, to, rest) = change
    t.event(at, fn() { on.set(to) })
    let mut was = under()
    let mut m = at
    while m <= at + 800.0 {
      t.at(m)
      t.frame(390.0, 844.0) |> ignore
      let y = under()
      assert_true((y - was).abs() < 3.0, msg="shown \{to}: 下 from \{was} to \{y} at once at \{m}")
      was = y
      m = m + 1.0
    }
    assert_eq(under(), rest, msg="shown \{to}: 下 at \{under()} at rest")
  }
  assert_false(t.clock_read())
}

///|
test "a pick leaving over a time in a column that stretches what it holds, its side a ground with its words centred, for a narrower one or for nothing: what fades drawn where and as big as it was in every frame of its fade" {
  for to_nothing in [false, true] {
    let wide = @signals.signal(true, same=fn(a, b) { a == b })
    let t = @view.Tree::new(fn(root) {
      root.pick(leave=pick_leave_ms, fn() { wide.get() }, fn(v, k) {
        if k {
          v.height(Is(Some(30.0))).ground(Is(0x3366CCFFL)).words(Is("铺满")).words_centered(Is(true)) |> ignore
        } else if !to_nothing {
          v.width(Is(Some(100.0))).height(Is(Some(30.0))).words(Is("窄")) |> ignore
        }
      })
      root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    let say = "to nothing \{to_nothing}"
    let rect = fn() {
      t.drawn().iter().find_first(fn(d) { d.words == "铺满" }).map(fn(d) { (d.x, d.y, d.w, d.h, d.alpha) })
    }
    guard rect() is Some((x0, y0, w0, h0, _)) else { fail("\{say}: 铺满 not drawn") }
    assert_eq(w0, 390.0, msg="\{say}: 铺满 \{w0} wide, not stretched across")
    t.event(100.0, fn() { wide.set(false) })
    let mut m = 100.0
    while m <= 100.0 + pick_leave_ms + 600.0 {
      t.at(m)
      t.frame(390.0, 844.0) |> ignore
      match rect() {
        Some((x, y, w, h, a)) if a > 0.0 =>
          assert_true(
            x == x0 && y == y0 && w == w0 && h == h0,
            msg="\{say}: 铺满 drawn at \{x},\{y} \{w}x\{h} at \{m}, \{x0},\{y0} \{w0}x\{h0} before the change",
          )
        _ => ()
      }
      m = m + 1.0
    }
    assert_eq(pick_leave_alpha(t, "铺满"), 0.0)
    assert_false(t.clock_read())
  }
}
