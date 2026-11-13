// A key of a page's list (View::scrolls_window) coming or going by data on its way is seen by how much of its block
// shows, as an old list's row coming or going where it is (ui's row_held_look; the user, 2026-10-31 and 2026-11-08):
// none at half its size or less, whole at its size (row_seen_at), the room's cut of it soft (View::cuts_softly); one set
// out from all its height given back whole from the first look. At every look 10 ms apart, in one jump and at 60, 120,
// 24 and 7 a second: how opaque its words are drawn against how much of its block shows (the block cut to itself as it
// goes: the nearest holder that clips its words, as tall as it shows), within a hundredth.

///|
/// At each look of the keys' change at su_change_at on, from the look before it: how opaque the words `w` are drawn and
/// how tall the block holding them shows (rc_none, rc_none where they are not drawn).
fn ks_walk(c : OmCase, events : Array[(Double, () -> Unit)], w : String, rate : Double) -> Array[(Double, Double)] {
  let looks = []
  let mut at = su_sent_at
  while at <= su_change_at + su_after_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  let all = rc_walk(c.tree, events, looks, rate, fn() {
    let held = c.tree.drawn_held()
    let mut out = (rc_none, rc_none)
    for i, e in held {
      let (d, _, _) = e
      guard d.words == w else { continue }
      // (the nearest holder that clips it: its block, cut to itself on its way)
      let mut h = held[i].1
      let mut tall = rc_none
      while h >= 0 {
        let (hd, up, _) = held[h]
        if hd.clips {
          tall = hd.h
          break
        }
        h = up
      }
      out = (d.alpha, tall)
    }
    out
  })
  let first = all.length() - (looks.length() - su_look(su_change_at) + 1)
  all[first:].to_owned()
}

///|
/// Where among `seen` the words are drawn otherwise opaque than row_seen_at has a block `whole` tall showing as tall
/// as it does, by more than a hundredth: none, or the look and what.
fn ks_off(seen : Array[(Double, Double)], whole : Double) -> String? {
  for i, s in seen {
    guard s.0 != rc_none && s.1 != rc_none else { continue }
    let want = @view.row_seen_at(s.1 / whole)
    if (s.0 - want).abs() > 0.01 {
      return Some("look \{i}: drawn \{s.0} opaque, its block \{s.1} of \{whole} showing, \{want} wanted")
    }
  }
  None
}

///|
test "a key coming at a page's list's end with nothing given back (no room, no part, the foot still), 64 tall: at every look as opaque as how much of its block shows has it, none at half or less, whole at rest" {
  for rate in rc_rates {
    let c = om_case(44.0, 0.0, 64.0)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70])) }),
      (su_change_at, fn() { c.keys.set(om_keys([70, 72])) }),
    ]
    let seen = ks_walk(c, events, "行72", rate)
    let at = "at \{rate} a second"
    match ks_off(seen, 64.0) {
      Some(w) => fail("\{at}: \{w}")
      None => ()
    }
    // (on its way at all: some look with it half shown or less, drawn none)
    assert_true(
      seen.iter().any(fn(s) { s.1 != rc_none && s.1 < 32.0 && s.0 == 0.0 }),
      msg="\{at}: never seen at half or less, drawn none: \{Repr(seen)}",
    )
    let rest = seen[seen.length() - 1]
    assert_true((rest.0 - 1.0).abs() < 0.001, msg="\{at}: at rest drawn \{rest.0} opaque")
  }
}

///|
test "a key coming among a page's list's keys (over the last, which stays), 64 tall: at every look as opaque as how much of its block shows has it; a key going by its way (not said to leave its room): the same on its way out" {
  for rate in rc_rates {
    // (72 coming between 9 and 70)
    let c = om_case(44.0, 0.0, 64.0)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70])) }),
      (su_change_at, fn() { c.keys.set(om_keys([72, 70])) }),
    ]
    let seen = ks_walk(c, events, "行72", rate)
    match ks_off(seen, 64.0) {
      Some(w) => fail("among, at \{rate} a second: \{w}")
      None => ()
    }
    // (72 going by its way from under 70)
    let c = om_case(44.0, 0.0, 64.0)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70, 72])) }),
      (su_change_at, fn() { c.keys.set(om_keys([70])) }),
    ]
    let seen = ks_walk(c, events, "行72", rate)
    match ks_off(seen, 64.0) {
      Some(w) => fail("going, at \{rate} a second: \{w}")
      None => ()
    }
  }
}

///|
test "a key coming at a page's list's end set out from all its height (a room of 80 given back), 64 tall: whole from the first look" {
  for rate in rc_rates {
    let c = om_case(80.0, 0.0, 64.0)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(om_keys([70])) }),
      (su_line_at, fn() { c.keys.set(om_keys([70, 50])) }),
      (su_gone_at, fn() { c.keys.set(om_keys([70])) }),
      (su_change_at, fn() { c.keys.set(om_keys([70, 72])) }),
    ]
    let looks = ks_walk(c, events, "行72", rate)
    for i, s in looks {
      if i > 0 && s.0 != rc_none {
        assert_true((s.0 - 1.0).abs() < 0.001, msg="at \{rate} a second, look \{i}: drawn \{s.0} opaque")
      }
    }
  }
}
