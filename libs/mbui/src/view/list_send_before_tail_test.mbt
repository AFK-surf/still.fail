// A key that comes before keys that stay under it is at the foot for the one reading (the coordinator of the
// migration, 2026-11-14: the second principle said for this case, not a new rule; the chat's agent's line under the
// words sent, the next words put before it). The list's two rules for a send hold for the stretch from the top of the
// last staying key before the coming keys (L) down to the column's end, whatever stays under them: what a part closing
// at once gives back there (L's time line), the room under the last block, the pinned foot's shrink, all go to the
// coming key, which sets out from as tall as that against L from the first frame; what stays under it (the line) keeps
// its place against the column's end; nothing over it or under it steps. Then the key opens the rest of its way and
// what is over goes up by that, once. Looked at every 10 ms, in one jump and at 60, 120, 24 and 7 a second (rc_walk).

///|
/// When the foot grows (before the change), the change, a second change while the first's way goes, the line let go
/// after all rests; how long a look goes on past the change.
let bt_grown_at : Double = 1600.5

///|
let bt_change_at : Double = 2500.5

///|
let bt_again_at : Double = 2620.5

///|
let bt_gone_at : Double = 4500.5

///|
let bt_after_ms : Double = 1200.0

///|
/// The rows read (0 to 9, 40 each), the sent words' block (70: its words 40, then its part 部 said at once, shown only
/// while it is the last of its run), the agent's line under it (50, 44, 线, said to leave its room), and what comes
/// before the line: 72 (its words 24 at its top, `next_h` in all) and 73 (40, its words 24 at its top).
priv struct BtCase {
  tree : @view.Tree
  keys : @signals.Signal[Array[Int]]
  foot : @signals.Signal[Double]
  part : @signals.Signal[Bool]
  foot_box : Ref[@view.View?]
}

///|
fn bt_case(part_h : Double, next_h : Double) -> BtCase {
  let keys = @signals.signal(bt_keys([70, 50]), same=fn(a, b) { a == b })
  let foot = @signals.signal(su_foot, same=fn(a, b) { a == b })
  let part = @signals.signal(true, same=fn(a, b) { a == b })
  let foot_box : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(
        @view.Scroll::list(),
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
                at_once=true,
              )
            }
          } else if k == 72 || k == 73 {
            let h = if k == 72 { next_h } else { 40.0 }
            b.box(fn(w) { w.height(Is(Some(24.0))).shrink(Is(0.0)).words(Is("行\{k}")) |> ignore }) |> ignore
            b.box(fn(r) { r.height(Is(Some(h - 24.0))).shrink(Is(0.0)) |> ignore }) |> ignore
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
  tree.frame(390.0, 844.0) |> ignore
  { tree, keys, foot, part, foot_box }
}

///|
fn bt_keys(more : Array[Int]) -> Array[Int] {
  let all = Array::makei(10, fn(i) { i })
  all.append(more)
  all
}

///|
/// One look: where 行9, 行70, 行72, 行73 and 线 are drawn (rc_none: not), the pinned foot's top as drawn, whether 部 is.
priv struct BtLook {
  y9 : Double
  y70 : Double
  y72 : Double
  y73 : Double
  line : Double
  foot_top : Double
  part : Bool
}

///|
fn bt_look(c : BtCase) -> BtLook {
  let foot_top = match c.foot_box.val {
    Some(b) => b.placed_window_now().1
    None => 400.0 - c.foot.untracked()
  }
  {
    y9: rc_y(c.tree, "行9"),
    y70: rc_y(c.tree, "行70"),
    y72: rc_y(c.tree, "行72"),
    y73: rc_y(c.tree, "行73"),
    line: rc_y(c.tree, "线"),
    foot_top,
    part: om_seen(c.tree, "部"),
  }
}

///|
/// What the change gives back and brings: L's part closing at once in it, the foot grown by `foot` before and back in
/// it (declared, or at once), the keys put before the line in it (`come`), and in a second change `again` more.
priv struct BtGive {
  part : Bool
  foot : Double
  declared : Bool
  come : Array[Int]
  again : Array[Int]
}

///|
/// The case walked to the change's rest at `rate`: each look from the one before the change on.
fn bt_walk(c : BtCase, give : BtGive, rate : Double) -> Array[BtLook] {
  let events : Array[(Double, () -> Unit)] = []
  if give.foot > 0.0 {
    events.push((bt_grown_at, fn() { c.foot.set(su_foot + give.foot) }))
  }
  events.push((bt_change_at, fn() {
    if give.foot > 0.0 {
      if give.declared {
        c.foot_box.val.unwrap().resizes() |> ignore
      }
      c.foot.set(su_foot)
    }
    if give.part {
      c.part.set(false)
    }
    c.keys.set(bt_keys([70] + give.come + [50]))
  }))
  if give.again.length() > 0 {
    events.push((bt_again_at, fn() { c.keys.set(bt_keys([70] + give.come + give.again + [50])) }))
  }
  let looks = []
  let mut at = bt_change_at - rc_look_ms
  while at <= bt_change_at + bt_after_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  rc_walk(c.tree, events, looks, rate, fn() { bt_look(c) })
}

///|
/// What is wrong among `seen` (0: the look before the change): 部 drawn after it; 行9 down from the highest it was;
/// the line otherwise against the foot's top than before; the first come key's words otherwise against L's than they
/// rest (where `set_out`), the second's otherwise against the first's (where `two`).
fn bt_faults(seen : Array[BtLook], set_out? : Bool = true, two? : Bool = false) -> Array[String] {
  let out = []
  let rest = seen[seen.length() - 1]
  let first = seen[0]
  let under = first.foot_top - first.line
  let mut high = first.y9
  for i in 1..<seen.length() {
    let s = seen[i]
    if s.part {
      out.push("look \{i}: L's part drawn")
    }
    if s.y9 != rc_none {
      if s.y9 > high + 0.5 {
        out.push("look \{i}: 行9 down to \{s.y9}, \{high} before")
      }
      if s.y9 < high {
        high = s.y9
      }
    }
    if s.line == rc_none {
      out.push("look \{i}: the line not drawn")
    } else if ((s.foot_top - s.line) - under).abs() > 0.5 {
      out.push("look \{i}: the line \{s.foot_top - s.line} over the foot's top, \{under} before")
    }
    if set_out && s.y72 != rc_none && s.y70 != rc_none && ((s.y72 - s.y70) - (rest.y72 - rest.y70)).abs() > 0.5 {
      out.push("look \{i}: 行72 \{s.y72 - s.y70} under 行70, \{rest.y72 - rest.y70} at rest")
    }
    if two && s.y73 != rc_none && s.y72 != rc_none && ((s.y73 - s.y72) - (rest.y73 - rest.y72)).abs() > 0.5 {
      out.push("look \{i}: 行73 \{s.y73 - s.y72} under 行72, \{rest.y73 - rest.y72} at rest")
    }
  }
  if out.length() > 4 {
    return out[:4].to_owned() + ["… \{out.length()} in all"]
  }
  out
}

///|
/// Fails saying `faults` where there are any.
fn bt_none(faults : Array[String], at : String) -> Unit raise {
  if faults.length() > 0 {
    fail("\{at}: " + faults.join("; "))
  }
}

///|
/// How far 行9 is up at rest from the look before the change.
fn bt_up(seen : Array[BtLook]) -> Double {
  seen[0].y9 - seen[seen.length() - 1].y9
}

///|
test "a key put before the line under the sent words, their part of 22 closing at once in that change, a key of 64: from the change's first frame the key as tall as the 22 given back, its words at rest against L's; the line where it was against the column's end; nothing over down; up 42 at rest" {
  for rate in rc_rates {
    let c = bt_case(22.0, 64.0)
    let seen = bt_walk(c, { part: true, foot: 0.0, declared: false, come: [72], again: [] }, rate)
    let at = "at \{rate} a second"
    bt_none(bt_faults(seen), at)
    // (in the change's first look nothing over has stepped: what it opens past the 22 is on its way)
    assert_true(seen[1].y9 <= seen[0].y9 + 0.5 && seen[0].y9 - seen[1].y9 < 42.0 * 0.5, msg="\{at}: 行9 \{seen[0].y9} to \{seen[1].y9} in the first look")
    assert_true((bt_up(seen) - 42.0).abs() < 0.5, msg="\{at}: up \{bt_up(seen)}, 42 wanted")
  }
}

///|
test "a key of 64 put before the line, nothing given back: it sets out from none; what is over up only, 64 at rest; the line never moves against the column's end" {
  for rate in rc_rates {
    let c = bt_case(0.0, 64.0)
    let seen = bt_walk(c, { part: false, foot: 0.0, declared: false, come: [72], again: [] }, rate)
    let at = "at \{rate} a second"
    bt_none(bt_faults(seen, set_out=false), at)
    assert_true((bt_up(seen) - 64.0).abs() < 0.5, msg="\{at}: up \{bt_up(seen)}, 64 wanted")
  }
}

///|
test "two keys put before the line in one change (64 and 40), the part of 22 closing at once: the first's words at rest against L's, the second's against the first's, at every look; the line where it was; nothing down; up 82 at rest" {
  for rate in rc_rates {
    let c = bt_case(22.0, 64.0)
    let seen = bt_walk(c, { part: true, foot: 0.0, declared: false, come: [72, 73], again: [] }, rate)
    let at = "at \{rate} a second"
    bt_none(bt_faults(seen, two=true), at)
    assert_true((bt_up(seen) - 82.0).abs() < 0.5, msg="\{at}: up \{bt_up(seen)}, 82 wanted")
  }
}

///|
test "a second key put before the line 120 ms after the first, the first still on its way: one way up, nothing over down, the line where it was against the column's end; up 82 at rest" {
  for rate in rc_rates {
    let c = bt_case(22.0, 64.0)
    let seen = bt_walk(c, { part: true, foot: 0.0, declared: false, come: [72], again: [73] }, rate)
    let at = "at \{rate} a second"
    bt_none(bt_faults(seen, set_out=false), at)
    assert_true((bt_up(seen) - 82.0).abs() < 0.5, msg="\{at}: up \{bt_up(seen)}, 82 wanted")
  }
}

///|
test "the foot back 49.5 in the change that puts a key of 132 before the line (at once, and declared): the line keeps its place against the foot's top, the key's words at rest against L's at every look, nothing over down; up 82.5 at rest" {
  for declared in [false, true] {
    for rate in rc_rates {
      let c = bt_case(0.0, 132.0)
      let seen = bt_walk(c, { part: false, foot: 49.5, declared, come: [72], again: [] }, rate)
      let at = "declared \{declared}, at \{rate} a second"
      bt_none(bt_faults(seen), at)
      assert_true((bt_up(seen) - 82.5).abs() < 0.5, msg="\{at}: up \{bt_up(seen)}, 82.5 wanted")
    }
  }
}

///|
test "the line let go by itself once all rests, said to leave its room: as ever, it fades where it is, nothing over it moving" {
  for rate in rc_rates {
    let c = bt_case(22.0, 64.0)
    bt_walk(c, { part: true, foot: 0.0, declared: false, come: [72], again: [] }, rate) |> ignore
    let looks = []
    let mut at = bt_gone_at - rc_look_ms
    while at <= bt_gone_at + bt_after_ms {
      looks.push(at)
      at = at + rc_look_ms
    }
    let seen = rc_walk(
      c.tree,
      [(bt_gone_at, fn() { c.keys.set(bt_keys([70, 72])) })],
      looks,
      rate,
      from=bt_change_at + bt_after_ms,
      fn() { bt_look(c) },
    )
    let at = "at \{rate} a second"
    for i, s in seen {
      assert_true((s.y72 - seen[0].y72).abs() <= 0.5 && (s.y9 - seen[0].y9).abs() <= 0.5, msg="\{at}, look \{i}: 行72 \{seen[0].y72} to \{s.y72}, 行9 \{seen[0].y9} to \{s.y9}")
    }
    assert_eq(seen[seen.length() - 1].line, rc_none, msg="\{at}: the line still drawn at rest")
  }
}
