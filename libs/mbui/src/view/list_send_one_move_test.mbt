// A key that comes at the end of a page's list as one move (the coordinator of the migration's rule, 2026-11-13, for
// the owner's 「这样不好吧」 at the films of #5960: as 再看看 was sent, the message before it closed its time line cut, and
// the new bubble stood low under it, then came up). What the last key that stays (L) shows only while it is the last of
// its run, the row says at once (`show(at_once=true)`: the list cannot tell a part's cause, and a fold stays a fold), so
// in the change by which a key comes at the end (by data) it is not drawn from that frame, its room closed in that
// layout, as the old page built the row again without its time line. The key coming sets out from as tall as all that
// change gives back under L's top (the room there, L's own shrink, the pinned foot's shrink), never taller than itself,
// two or more in their order, each up to its own height, in the one way they were said in; so what it holds is at its
// resting place against L at every frame; what is over goes up by the rest only, on the one way, the new row riding on
// it. No words in the last two rows drawn cut: each is wholly inside what is drawn of it or not drawn at all; the one
// edge that may cross words is the pinned foot's top (the new row coming up from behind the composer: covered by the
// foot, not cut in mid air). Not this rule (as before): a part of another row closing in that change, a part of L said
// by its way, a key the page lets go at the foot. Looked at every 10 ms, in one jump and at 60, 120, 24 and 7 a second
// (rc_walk, list_rows_come_test's); on device pixels at 2 and 3 where it says the same place.

///|
/// The rows over (0 to 9, 40 each; row 9's own part, 18, where said), the sent words' block (70: its words 40, then its
/// part, words 部, that goes as a key comes after it), the agent's line (50, said to leave its room), the key that comes
/// (72: its words at its top, 行72).
priv struct OmCase {
  tree : @view.Tree
  keys : @signals.Signal[Array[Int]]
  foot : @signals.Signal[Double]
  part : @signals.Signal[Bool]
  part9 : @signals.Signal[Bool]
  foot_box : Ref[@view.View?]
  next_h : Double
}

///|
/// The case on grid `g` (none where 0): the line `line_h`, L's part `part_h` (none where 0), the key `next_h`, row 9's
/// own part where `part9`. Drawn once, at 0. `reduced`: its motion reduced. `part_at_once`: L's part said at once (a part
/// the row shows only while it is the last of its run: the row's to say, the list cannot tell its cause); else by its
/// way (a fold).
fn om_case(
  line_h : Double,
  part_h : Double,
  next_h : Double,
  g? : Double = 0.0,
  part9? : Bool = false,
  reduced? : Bool = false,
  part_at_once? : Bool = true,
) -> OmCase {
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let foot = @signals.signal(su_foot, same=fn(a, b) { a == b })
  let part = @signals.signal(true, same=fn(a, b) { a == b })
  let part9_on = @signals.signal(true, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::list()
  let foot_box : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { true },
        leaves_room=fn(k) { k == 50 },
        foot=fn(f) {
          f.box(fn(b) {
            b.height(By(fn() { Some(foot.get()) })).shrink(Is(0.0)) |> ignore
            foot_box.val = Some(b)
          })
          |> ignore
        },
        fn(b, k) {
          if k == 70 {
            b.box(fn(w) { w.height(Is(Some(40.0))).shrink(Is(0.0)).words(Is("行70")) |> ignore }) |> ignore
            if part_h > 0.0 {
              b.show(
                fn() { part.get() },
                fn(p) { p.height(Is(Some(part_h))).shrink(Is(0.0)).words(Is("部")) |> ignore },
                at_once=part_at_once,
              )
            }
          } else if k == 9 && part9 {
            b.box(fn(w) { w.height(Is(Some(40.0))).shrink(Is(0.0)).words(Is("行9")) |> ignore }) |> ignore
            b.show(fn() { part9_on.get() }, fn(p) { p.height(Is(Some(18.0))).shrink(Is(0.0)).words(Is("部9")) |> ignore })
          } else {
            if k == 72 {
              // (its words a line at its top, the rest of it under them)
              b.box(fn(w) { w.height(Is(Some(24.0))).shrink(Is(0.0)).words(Is("行72")) |> ignore }) |> ignore
              b.box(fn(r) { r.height(Is(Some(next_h - 24.0))).shrink(Is(0.0)) |> ignore }) |> ignore
            } else if k == 73 {
              // (a second key come with it, 40: its words a line at its top)
              b.box(fn(w) { w.height(Is(Some(24.0))).shrink(Is(0.0)).words(Is("行73")) |> ignore }) |> ignore
              b.box(fn(r) { r.height(Is(Some(16.0))).shrink(Is(0.0)) |> ignore }) |> ignore
            } else {
              let h = if k == 50 { line_h } else { 40.0 }
              b.height(Is(Some(h))).words(Is(if k == 50 { "线" } else { "行\{k}" })) |> ignore
            }
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  if g > 0.0 {
    tree.set_rows_grid(g)
  }
  if reduced {
    tree.reduces_motion(fn() { true })
  }
  tree.frame(390.0, 844.0) |> ignore
  { tree, keys, foot, part, part9: part9_on, foot_box, next_h }
}

///|
fn om_keys(more : Array[Int]) -> Array[Int] {
  let all = Array::makei(10, fn(i) { i })
  all.append(more)
  all
}

///|
/// What is looked at each look: where 行9, 行70, 行72 are drawn (rc_none: not), whether 部 and 部9 are drawn (seen),
/// and what is drawn cut among the last two rows' words (none, or what).
priv struct OmLook {
  y9 : Double
  y70 : Double
  y72 : Double
  y73 : Double
  part : Bool
  part9 : Bool
  cut : String?
}

///|
/// Where the words `w` are drawn cut in `t`: their box neither wholly inside what clips them (each holder said to clip
/// what it holds) nor wholly out of it; an edge at the pinned foot's top (`foot_top`) is no cut (the foot covers them).
fn om_cut(t : @view.Tree, words : Array[String], foot_top : Double) -> String? {
  let held = t.drawn_held()
  for i, e in held {
    let (d, _, _) = e
    guard words.contains(d.words) && d.alpha > 0.0 else { continue }
    let mut lo = @double.neg_infinity
    let mut hi = @double.infinity
    let mut h = held[i].1
    while h >= 0 {
      let (c, up, _) = held[h]
      if c.clips {
        lo = if c.y > lo { c.y } else { lo }
        hi = if c.y + c.h < hi { c.y + c.h } else { hi }
      }
      h = up
    }
    let top = d.y
    let foot = d.y + d.h
    let seen_lo = if top > lo { top } else { lo }
    let seen_hi = if foot < hi { foot } else { hi }
    guard seen_hi - seen_lo > 0.01 else { continue }
    let whole = seen_lo <= top + 0.01 && seen_hi >= foot - 0.01
    let at_foot_top = (seen_hi - foot_top).abs() < 0.51 && seen_lo <= top + 0.01
    if !whole && !at_foot_top {
      return Some("\{d.words} drawn \{top}..\{foot}, seen \{seen_lo}..\{seen_hi}")
    }
  }
  None
}

///|
fn om_seen(t : @view.Tree, w : String) -> Bool {
  t.drawn().iter().any(fn(d) { d.words == w && d.alpha > 0.0 })
}

///|
/// What gives room back in the change, and what comes.
priv struct OmGive {
  room : Bool // the line gone before, leaving its room
  foot : Double // the foot grown by this before, back in the change (0: still)
  declared : Bool // its going back declared (View::resizes), or at once
  part : Bool // L's part going in the change
  part9 : Bool // row 9's part going in the change
  comes : Bool // the key coming in the change
  read_up : Double // read up so far before the change (0: at its foot)
}

///|
/// The case walked from su_sent_at to the change's rest at `rate`, as `give` says (`more`: keys come after 72 in that
/// change): each look from the one before the change on.
fn om_walk(c : OmCase, give : OmGive, rate : Double, more? : Array[Int] = []) -> Array[OmLook] {
  let events : Array[(Double, () -> Unit)] = [(su_sent_at, fn() { c.keys.set(om_keys([70])) })]
  if give.room {
    events.push((su_line_at, fn() { c.keys.set(om_keys([70, 50])) }))
    events.push((su_gone_at, fn() { c.keys.set(om_keys([70])) }))
  }
  if give.foot > 0.0 {
    events.push((su_grown_at, fn() { c.foot.set(su_foot + give.foot) }))
  }
  events.push((su_change_at, fn() {
    if give.foot > 0.0 {
      if give.declared {
        c.foot_box.val.unwrap().resizes() |> ignore
      }
      c.foot.set(su_foot)
    }
    if give.part {
      c.part.set(false)
    }
    if give.part9 {
      c.part9.set(false)
    }
    if give.comes {
      c.keys.set(om_keys([70, 72] + more))
    }
  }))
  let looks = []
  let mut at = su_sent_at
  while at <= su_change_at + su_after_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  if give.read_up > 0.0 {
    rc_walk(c.tree, events.filter(fn(e) { e.0 < su_change_at }), [su_change_at - 300.0], rate, fn() { () }) |> ignore
    c.tree.wheel_at(150.0, 100.0, 0.0, -give.read_up, 0, su_change_at - 290.0) |> ignore
  }
  let from = if give.read_up > 0.0 { su_change_at - 290.0 } else { 0.0 }
  let all = rc_walk(
    c.tree,
    events.filter(fn(e) { e.0 >= from }),
    looks.filter(fn(t) { t > from }),
    rate,
    from~,
    fn() {
      // (the pinned foot's top as it is drawn at this frame, read off its box where it is placed: a declared foot is still
      // tall as the key sets out, and covers it)
      let foot_top = match c.foot_box.val {
        Some(b) => b.placed_window_now().1
        None => 400.0 - c.foot.untracked()
      }
      {
        y9: rc_y(c.tree, "行9"),
        y70: rc_y(c.tree, "行70"),
        y72: rc_y(c.tree, "行72"),
        y73: rc_y(c.tree, "行73"),
        part: om_seen(c.tree, "部"),
        part9: om_seen(c.tree, "部9"),
        cut: om_cut(c.tree, ["行70", "部", "行72", "行73"], foot_top),
      }
    },
  )
  let first = all.length() - (looks.length() - su_look(su_change_at) + 1)
  all[first:].to_owned()
}

///|
/// Where among `seen` (0: the look before the change) the key's words stand otherwise against L's than they rest
/// (on device pixels on grid `g` where it is one), or L's part is drawn, or words are drawn cut: none, or what.
fn om_one_move(seen : Array[OmLook], g : Double) -> String? {
  let px = fn(y : Double) { if g > 0.0 { (y * g + 0.5).floor() } else { y } }
  let rest = seen[seen.length() - 1]
  let want = px(rest.y72) - px(rest.y70)
  for i in 1..<seen.length() {
    let s = seen[i]
    if s.part {
      return Some("look \{i}: L's part drawn")
    }
    match s.cut {
      Some(w) => return Some("look \{i}: \{w}")
      None => ()
    }
    if s.y72 != rc_none && s.y70 != rc_none {
      let d = px(s.y72) - px(s.y70)
      if (d - want).abs() > (if g > 0.0 { 0.0 } else { 0.5 }) {
        return Some("look \{i}: the key's words \{d} under L's, \{want} at rest")
      }
    }
  }
  None
}

///|
/// How far up L's words are at rest from where they were the look before the change.
fn om_up(seen : Array[OmLook]) -> Double {
  seen[0].y70 - seen[seen.length() - 1].y70
}

///|
/// Where among `seen` 行9 went down by more than half a point against the look before the change: none, or the look.
fn om_down(seen : Array[OmLook]) -> String? {
  for i, s in seen {
    if s.y9 != rc_none && s.y9 > seen[0].y9 + 0.5 {
      return Some("look \{i}: 行9 at \{s.y9}, \{seen[0].y9} before")
    }
  }
  None
}

///|
/// The room under the last block and over the foot, as drawn: 行72's foot to the foot's top.
fn om_room(c : OmCase) -> Double {
  400.0 - c.foot.untracked() - (rc_y(c.tree, "行72") + c.next_h)
}

///|
test "A. the films' scene: a room of 52, L's part of 22 going as a key of 64 comes: L's part not drawn from the change's frame, the key's words at their resting place against L's at every look (device pixels at 2 and 3 alike), nothing over L moving, the room 10 at rest, no words drawn cut" {
  for g in [0.0, 2.0, 3.0] {
    for rate in rc_rates {
      let c = om_case(52.0, 22.0, 64.0, g~)
      let seen = om_walk(c, { room: true, foot: 0.0, declared: false, part: true, part9: false, comes: true, read_up: 0.0 }, rate)
      let at = "grid \{g}, at \{rate} a second"
      match om_one_move(seen, g) {
        Some(w) => fail("\{at}: \{w}")
        None => ()
      }
      match om_down(seen) {
        Some(w) => fail("\{at}: \{w}")
        None => ()
      }
      assert_true(om_up(seen).abs() < 0.5, msg="\{at}: L up \{om_up(seen)}, none wanted")
      assert_true((om_room(c) - 10.0).abs() < 0.5, msg="\{at}: the room \{om_room(c)} at rest, 10 wanted")
    }
  }
}

///|
test "A'. 小屏's numbers: a room of 44, L's part of 22, a key of 66.75: what is over up by the rest only (0.75), the key's words at their resting place against L's at every look, no words drawn cut" {
  for rate in rc_rates {
    let c = om_case(44.0, 22.0, 66.75)
    let seen = om_walk(c, { room: true, foot: 0.0, declared: false, part: true, part9: false, comes: true, read_up: 0.0 }, rate)
    let at = "at \{rate} a second"
    match om_one_move(seen, 0.0) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    match om_down(seen) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    assert_true((om_up(seen) - 0.75).abs() < 0.5, msg="\{at}: L up \{om_up(seen)}, 0.75 wanted")
  }
}

///|
test "B. no room, L's part of 22 going as a key of 64 comes: L up 42 on the way, the key's words at their resting place against L's from the first look, L's part not drawn from the first, no words drawn cut" {
  for rate in rc_rates {
    let c = om_case(44.0, 22.0, 64.0)
    let seen = om_walk(c, { room: false, foot: 0.0, declared: false, part: true, part9: false, comes: true, read_up: 0.0 }, rate)
    let at = "at \{rate} a second"
    match om_one_move(seen, 0.0) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    match om_down(seen) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    assert_true((om_up(seen) - 42.0).abs() < 0.5, msg="\{at}: L up \{om_up(seen)}, 42 wanted")
  }
}

///|
test "C. no room, the foot back 49.5 in that change (three lines sent), a key of 132: what is over up 82.5, the key's words at their resting place against L's throughout, no words drawn cut but at the foot's top" {
  for rate in rc_rates {
    let c = om_case(44.0, 0.0, 132.0)
    let seen = om_walk(c, { room: false, foot: 49.5, declared: false, part: false, part9: false, comes: true, read_up: 0.0 }, rate)
    let at = "at \{rate} a second"
    match om_one_move(seen, 0.0) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    match om_down(seen) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    assert_true((om_up(seen) - 82.5).abs() < 0.5, msg="\{at}: L up \{om_up(seen)}, 82.5 wanted")
  }
}

///|
test "D. read up 30 (L in sight), a key comes at the end as L's part goes: L's part not drawn from the change's frame, what is read stays" {
  for rate in rc_rates {
    let c = om_case(44.0, 22.0, 64.0)
    let seen = om_walk(c, { room: false, foot: 0.0, declared: false, part: true, part9: false, comes: true, read_up: 30.0 }, rate)
    let at = "at \{rate} a second"
    for i in 1..<seen.length() {
      assert_false(seen[i].part, msg="\{at}, look \{i}: L's part drawn")
      assert_true((seen[i].y9 - seen[0].y9).abs() <= 0.5, msg="\{at}, look \{i}: 行9 at \{seen[i].y9}, read at \{seen[0].y9}")
    }
  }
}

///|
test "E. guards, as before: a part of row 9 closing in that change closes by its way (drawn the look after); L's part said by its way (a fold) closing with a key coming and with none, by its way, the list ending nothing of it; the sent words let go at the foot as a key comes, by their way" {
  for rate in rc_rates {
    let at = "at \{rate} a second"
    // (row 9's part in the change a key comes, L with no part)
    let c = om_case(44.0, 0.0, 64.0, part9=true)
    let seen = om_walk(c, { room: false, foot: 0.0, declared: false, part: false, part9: true, comes: true, read_up: 0.0 }, rate)
    assert_true(seen[1].part9, msg="\{at}: row 9's part not drawn the look after the change (gone at once)")
    // (L's part said by its way, with a key coming and with none)
    for comes in [true, false] {
      let c = om_case(44.0, 22.0, 64.0, part_at_once=false)
      let seen = om_walk(c, { room: false, foot: 0.0, declared: false, part: true, part9: false, comes, read_up: 0.0 }, rate)
      assert_true(seen[1].part, msg="\{at}, a key coming \{comes}: L's part said by its way not drawn the look after (gone at once)")
    }
  }
  for rate in rc_rates {
    // (the sent words, not said to leave their room, let go at the foot as a key comes: closing by their way)
    let c = om_case(44.0, 22.0, 64.0)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70])) }),
      (su_change_at, fn() { c.keys.set(om_keys([72])) }),
    ]
    let seen = rc_walk(c.tree, events, [su_change_at - rc_look_ms, su_change_at + rc_look_ms], rate, fn() {
      om_seen(c.tree, "行70")
    })
    assert_true(seen[1], msg="at \{rate} a second: the sent words gone at once as they were let go")
  }
}

///|
test "F. motion reduced: A and B at once: in the change's frame L's part not drawn, the key at its place, the room 10 (A), L up 42 (B)" {
  for (room, up, left) in [(true, 0.0, 10.0), (false, 42.0, 0.0)] {
    for rate in rc_rates {
      let c = om_case(52.0, 22.0, 64.0, reduced=true)
      let seen = om_walk(c, { room, foot: 0.0, declared: false, part: true, part9: false, comes: true, read_up: 0.0 }, rate)
      let at = "reduced, room \{room}, at \{rate} a second"
      assert_false(seen[1].part, msg="\{at}: L's part drawn in the change's frame")
      assert_true((seen[0].y70 - seen[1].y70 - up).abs() < 0.5, msg="\{at}: L up \{seen[0].y70 - seen[1].y70} in the change's frame, \{up} wanted")
      assert_true((om_room(c) - left).abs() < 0.5, msg="\{at}: the room \{om_room(c)}, \{left} wanted")
    }
  }
}

///|
test "C'. the same as C with the foot's going back declared (View::resizes, on the list's one way): what is over never down, up 82.5 at rest, the key's words at their resting place against L's throughout, no words cut but at the foot's top" {
  for rate in rc_rates {
    let c = om_case(44.0, 0.0, 132.0)
    let seen = om_walk(c, { room: false, foot: 49.5, declared: true, part: false, part9: false, comes: true, read_up: 0.0 }, rate)
    let at = "at \{rate} a second"
    match om_one_move(seen, 0.0) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    match om_down(seen) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    assert_true((om_up(seen) - 82.5).abs() < 0.5, msg="\{at}: L up \{om_up(seen)}, 82.5 wanted")
  }
}

///|
test "E'. L's part said by its way, gone as a key comes, then the key taken away again (L last once more): the part comes back by its way, as any part does" {
  for rate in rc_rates {
    let c = om_case(44.0, 22.0, 64.0, part_at_once=false)
    om_walk(c, { room: false, foot: 0.0, declared: false, part: true, part9: false, comes: true, read_up: 0.0 }, rate)
    |> ignore
    let back_at = su_change_at + su_after_ms + 100.0
    let looks = [back_at - rc_look_ms]
    for i in 0..<100 {
      looks.push(back_at + i.to_double() * rc_look_ms)
    }
    let seen = rc_walk(
      c.tree,
      [
        (back_at, fn() {
          c.part.set(true)
          c.keys.set(om_keys([70]))
        }),
      ],
      looks,
      rate,
      from=su_change_at + su_after_ms,
      fn() {
        let ink = c.tree.drawn().fold(init=0.0, fn(m, d) { if d.words == "部" && d.alpha > m { d.alpha } else { m } })
        (ink, om_cut(c.tree, ["部"], 400.0 - c.foot.untracked()) is Some(_))
      },
    )
    let at = "at \{rate} a second"
    assert_true(seen[0].0 == 0.0, msg="\{at}: L's part drawn before it came back")
    // (by its way, as a key coming is drawn under a page's list: not seen at or under half its room, seen past it on
    // its way (some ink, not all of it), whole and at full ink at rest; till 2026-11-14 it was looked at 50 ms after,
    // drawn cut to itself: the coordinator of the migration, 2026-11-14, by the user's 2026-10-31 and 2026-11-08)
    if rate == 0.0 || rate >= 24.0 {
      assert_true(seen.iter().any(fn(s) { s.0 > 0.0 && s.0 < 1.0 }), msg="\{at}: L's part not seen on its way back")
    }
    let last = seen[seen.length() - 1]
    assert_true(last.0 == 1.0 && !last.1, msg="\{at}: L's part not whole at rest")
  }
}

///|
test "G. two keys come at the end in one change (a reply and a line with it), over a room of 52 and L's part of 22 going, 64 and 40: L's part not drawn from the change's frame, the first's words at their resting place against L's and the second's against the first's at every look, what is over up only (30 at rest), no words cut but at the foot's top" {
  for rate in rc_rates {
    let c = om_case(52.0, 22.0, 64.0)
    let seen = om_walk(c, { room: true, foot: 0.0, declared: false, part: true, part9: false, comes: true, read_up: 0.0 }, rate, more=[73])
    let at = "at \{rate} a second"
    match om_one_move(seen, 0.0) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    let rest = seen[seen.length() - 1]
    let want = rest.y73 - rest.y72
    for i in 1..<seen.length() {
      let s = seen[i]
      if s.y73 != rc_none && s.y72 != rc_none {
        assert_true(((s.y73 - s.y72) - want).abs() <= 0.5, msg="\{at}, look \{i}: the second's words \{s.y73 - s.y72} under the first's, \{want} at rest")
      }
    }
    match om_down(seen) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    assert_true((om_up(seen) - 30.0).abs() < 0.5, msg="\{at}: L up \{om_up(seen)}, 30 wanted")
  }
}
