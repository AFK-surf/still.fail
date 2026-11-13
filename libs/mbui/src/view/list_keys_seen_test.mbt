// A key of a page's list (View::scrolls_window) coming or going by data on its way draws what its block holds as an old
// list's row coming or going where it is (ui's row_held_look; the user, 2026-10-31 and 2026-11-08): as big as how much
// of its block shows, none at half its size or less, whole at its size (row_seen_at), so that nothing of it drawn lies
// past what shows (nothing cut); one set out from all its height given back whole from the first look. At every look
// 10 ms apart, in one jump and at 60, 120, 24 and 7 a second, its rows on no grid and on 3 pixels a point (as every
// device's host sets them): how opaque and how big its words are drawn against how much of its block shows (the block
// cut to itself as it goes: the nearest holder that clips its words, as tall as it shows), within a hundredth, and
// whether its words drawn at all opaque lie inside what shows of it.

///|
/// What a look sees of the words: how opaque they are drawn, how tall the block holding them shows, how big they are
/// drawn (rc_none, rc_none, 1 where they are not drawn), and how far they are drawn past what shows of their block (0:
/// inside it).
priv struct KsSeen {
  alpha : Double
  tall : Double
  scale : Double
  past : Double
}

///|
/// At each look of the keys' change at su_change_at on, from the look before it: what is seen of the words `w`.
fn ks_walk(c : OmCase, events : Array[(Double, () -> Unit)], w : String, rate : Double) -> Array[KsSeen] {
  let looks = []
  let mut at = su_sent_at
  while at <= su_change_at + su_after_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  let all = rc_walk(c.tree, events, looks, rate, fn() {
    let held = c.tree.drawn_held()
    let mut out = { alpha: rc_none, tall: rc_none, scale: 1.0, past: 0.0 }
    for i, e in held {
      let (d, _, _) = e
      guard d.words == w else { continue }
      // (the nearest holder that clips it: its block, cut to itself on its way)
      let mut h = held[i].1
      let mut tall = rc_none
      let mut past = 0.0
      while h >= 0 {
        let (hd, up, _) = held[h]
        if hd.clips {
          tall = hd.h
          past = dmax(
            dmax(hd.x - d.x, d.x + d.w - (hd.x + hd.w)),
            dmax(hd.y - d.y, d.y + d.h - (hd.y + hd.h)),
          )
          break
        }
        h = up
      }
      out = { alpha: d.alpha, tall, scale: c.tree.drawn_scale(d.id), past: dmax(past, 0.0) }
    }
    out
  })
  let first = all.length() - (looks.length() - su_look(su_change_at) + 1)
  all[first:].to_owned()
}

///|
/// The grids looked on: none (the Tester's own), and 3 pixels a point, a page's list's rows set on them as every device's
/// host sets them (ui's rows_on_pixels: Tree::set_rows_grid).
let ks_grids : Array[Double] = [0.0, 3.0]

///|
/// Each grid at each rate.
fn ks_runs() -> Array[(Double, Double)] {
  let out = []
  for g in ks_grids {
    for rate in rc_rates {
      out.push((g, rate))
    }
  }
  out
}

///|
/// What a fault says of grid `g`.
fn ks_on(g : Double) -> String {
  if g > 0.0 {
    ", rows on \{g} pixels a point"
  } else {
    ""
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// Where among `seen` the words are drawn otherwise opaque or big than how much of a block `whole` tall shows has them
/// by more than a hundredth, or drawn at all opaque past what shows of it: none, or the look and what.
fn ks_off(seen : Array[KsSeen], whole : Double) -> String? {
  for i, s in seen {
    guard s.alpha != rc_none && s.tall != rc_none else { continue }
    let p = if s.tall / whole > 1.0 { 1.0 } else { s.tall / whole }
    let want = @view.row_seen_at(p)
    if (s.alpha - want).abs() > 0.01 {
      return Some("look \{i}: drawn \{s.alpha} opaque, its block \{s.tall} of \{whole} showing, \{want} wanted")
    }
    if (s.scale - p).abs() > 0.01 {
      return Some("look \{i}: drawn \{s.scale} big, its block \{s.tall} of \{whole} showing, \{p} wanted")
    }
    if s.alpha > 0.0 && s.past > 0.01 {
      return Some(
        "look \{i}: drawn \{s.alpha} opaque \{s.past} past what shows of its block (\{s.tall} of \{whole})",
      )
    }
  }
  None
}

///|
test "a key coming at a page's list's end with nothing given back (no room, no part, the foot still), 64 tall: at every look as opaque and as big as how much of its block shows has it, nothing of it drawn past that, none at half or less, whole at rest" {
  for run in ks_runs() {
    let (g, rate) = run
    let c = om_case(44.0, 0.0, 64.0, g~)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70])) }),
      (su_change_at, fn() { c.keys.set(om_keys([70, 72])) }),
    ]
    let seen = ks_walk(c, events, "行72", rate)
    let at = "at \{rate} a second\{ks_on(g)}"
    match ks_off(seen, 64.0) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    // (on its way at all: some look with it half shown or less, drawn none)
    assert_true(
      seen.iter().any(fn(s) { s.tall != rc_none && s.tall < 32.0 && s.alpha == 0.0 }),
      msg="\{at}: never seen at half or less, drawn none: \{Repr(seen.map(fn(s) { (s.alpha, s.tall) }))}",
    )
    let rest = seen[seen.length() - 1]
    assert_true((rest.alpha - 1.0).abs() < 0.001, msg="\{at}: at rest drawn \{rest.alpha} opaque")
    assert_true((rest.scale - 1.0).abs() < 0.001, msg="\{at}: at rest drawn \{rest.scale} big")
  }
}

///|
test "a key coming among a page's list's keys (over the last, which stays), 64 tall: at every look as opaque and as big as how much of its block shows has it, nothing of it drawn past that; a key going by its way (not said to leave its room): the same on its way out" {
  for run in ks_runs() {
    let (g, rate) = run
    // (72 coming between 9 and 70)
    let c = om_case(44.0, 0.0, 64.0, g~)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70])) }),
      (su_change_at, fn() { c.keys.set(om_keys([72, 70])) }),
    ]
    let seen = ks_walk(c, events, "行72", rate)
    match ks_off(seen, 64.0) {
      Some(w) => fail("among, at \{rate} a second\{ks_on(g)}: \{w}")
      None => ()
    }
    // (72 going by its way from under 70)
    let c = om_case(44.0, 0.0, 64.0, g~)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70, 72])) }),
      (su_change_at, fn() { c.keys.set(om_keys([70])) }),
    ]
    let seen = ks_walk(c, events, "行72", rate)
    match ks_off(seen, 64.0) {
      Some(w) => fail("going, at \{rate} a second\{ks_on(g)}: \{w}")
      None => ()
    }
  }
}

///|
test "a key coming at a page's list's end set out from all its height (a room of 80 given back), 64 tall: whole and at its size from the first look" {
  for run in ks_runs() {
    let (g, rate) = run
    let c = om_case(80.0, 0.0, 64.0, g~)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70])) }),
      (su_line_at, fn() { c.keys.set(om_keys([70, 50])) }),
      (su_gone_at, fn() { c.keys.set(om_keys([70])) }),
      (su_change_at, fn() { c.keys.set(om_keys([70, 72])) }),
    ]
    let looks = ks_walk(c, events, "行72", rate)
    for i, s in looks {
      if i > 0 && s.alpha != rc_none {
        assert_true((s.alpha - 1.0).abs() < 0.001, msg="at \{rate} a second\{ks_on(g)}, look \{i}: drawn \{s.alpha} opaque")
        assert_true((s.scale - 1.0).abs() < 0.001, msg="at \{rate} a second\{ks_on(g)}, look \{i}: drawn \{s.scale} big")
      }
    }
  }
}
