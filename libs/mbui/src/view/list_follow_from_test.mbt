// A page's list following its foot, followed no further than a key's top (ListPlace::follow_from, a chat's answer come
// at its foot read from its top: the old list's Ctx::list_follow_from): the key coming by data on its way, the list
// keeps to its foot in every frame till that key's top comes to `margin` under what covers the list's top, and holds it
// there from then to its rest, never over it, nothing over it going down; so held, it is off its foot, and a key come
// after moves nothing that shows till it is taken to its foot again (ListPlace::to_end, the hand). A key that fits rests
// at its foot, and is held once it grows past. A key under it going leaving its room in the same change carries it over
// the margin none. The limit stands (not used up as it takes hold): held, the list is off its foot to every rule of it,
// however near; the column shrunk so it binds no more, at its foot and following; the hand, an ask or its key gone
// let it go. Each looked at every rc_look_ms, drawn in one jump and at 60, 120, 24 and 7 a second (rc_walk).

///|
/// What covers the list's top (a chat's bar), the margin under it the key followed is held at, and the list's pinned
/// foot.
let fw_cover : Double = 50.0

///|
let fw_margin : Double = 26.0

///|
let fw_foot : Double = 30.0

///|
/// The key followed (its head line fw_head over words as tall as its case says), the agent's line under it (said to go
/// leaving its room), and two to come after it.
let fw_key : Int = 70

///|
let fw_line : Int = 50

///|
let fw_head : Double = 16.0

///|
/// How long a look goes on past what it looks at.
let fw_after_ms : Double = 1200.0

///|
priv struct FwCase {
  tree : @view.Tree
  scroll : @view.Scroll
  place : @view.ListPlace[Int]
  keys : @signals.Signal[Array[Int]]
  tall : @signals.Signal[Double]
}

///|
/// A page's list 300 by 400 under a cover `cover` of keys 0 to 9 (a head line of 16 over words of 24, marked where what
/// is read starts), and fw_line (44) under them where `line`; following its foot, its pinned foot fw_foot tall. fw_key's
/// words `tall` (a signal), marked; 71 and 72 as the others. Drawn once, at 0.
fn fw_case(tall : Double, line? : Bool = false, cover? : Double = fw_cover) -> FwCase {
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let first = Array::makei(10, fn(i) { i })
  if line {
    first.push(fw_line)
  }
  let keys = @signals.signal(first, same=fn(a, b) { a == b })
  let tall = @signals.signal(tall, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        top_covered=fn() { cover },
        follows=fn() { true },
        leaves_room=fn(k) { k == fw_line },
        place~,
        foot=fn(f) { f.box(fn(g) { g.height(Is(Some(fw_foot))) |> ignore }) |> ignore },
        fn(b, k) {
          if k == fw_line {
            b.box(fn(w) { w.height(Is(Some(44.0))).words(Is("线")) |> ignore }) |> ignore
            return
          }
          b.box(fn(h) { h.height(Is(Some(fw_head))).words(Is("名\{k}")) |> ignore }) |> ignore
          b.box(fn(w) {
            if k == fw_key {
              w.height(By(fn() { Some(tall.get()) })) |> ignore
            } else {
              w.height(Is(Some(24.0))) |> ignore
            }
            w.words(Is("行\{k}")).read_from() |> ignore
          })
          |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, place, keys, tall }
}

///|
/// How far it is off its foot.
fn FwCase::off_foot(self : FwCase) -> Double {
  self.scroll.most() - self.scroll.at(self.tree)
}

///|
/// Keys 0 to 9, then `more`.
fn fw_keys(more : Array[Int]) -> Array[Int] {
  let all = Array::makei(10, fn(i) { i })
  all.append(more)
  all
}

///|
/// What a look reads: where fw_key's top is drawn (its head line's words; rc_none where none), where 9's words are, and
/// how far the list is off its foot.
fn FwCase::look(self : FwCase) -> (Double, Double, Double) {
  (rc_y(self.tree, "名\{fw_key}"), rc_y(self.tree, "行9"), self.off_foot())
}

///|
/// The case walked from `from` to `at` + fw_after_ms, `cause` done at `at`, at `rate`: each look.
fn FwCase::walk(
  self : FwCase,
  at : Double,
  cause : () -> Unit,
  rate : Double,
  from? : Double = 0.0,
) -> Array[(Double, Double, Double)] {
  let looks = []
  let mut t = at
  while t <= at + fw_after_ms {
    looks.push(t)
    t = t + rc_look_ms
  }
  rc_walk(self.tree, [(at, cause)], looks, rate, from~, fn() { self.look() })
}

///|
/// What is wrong with `ys` (each look's fw_key top, 9's words, how far off its foot) as a key followed from its top
/// `edge` under the list's: at every look, its top never over `edge`; the list at its foot, or the key's top at `edge`;
/// 9's words never down; at its end, the key's top at `edge` and the list off its foot. None: nothing.
fn fw_wrong(ys : Array[(Double, Double, Double)], edge : Double) -> String? {
  let mut nine = @double.infinity
  for i, y in ys {
    let (top, w9, off) = y
    if top != rc_none && top < edge - 0.01 {
      return Some("look \{i}: its top \{top} over \{edge}")
    }
    if top != rc_none && off > 0.01 && (top - edge).abs() > 0.01 {
      return Some("look \{i}: off its foot by \{off} with its top at \{top}, not \{edge}")
    }
    if w9 != rc_none {
      if w9 > nine + 0.01 {
        return Some("look \{i}: 9's words down, \{nine} → \{w9}")
      }
      nine = w9
    }
  }
  let (top, _, off) = ys[ys.length() - 1]
  if (top - edge).abs() > 0.01 || off < 1.0 {
    return Some("at rest: its top \{top}, off its foot by \{off}")
  }
  None
}

///|
test "follow_from: a key taller than what shows come at the foot on its way: the list at its foot till its top is the margin under the cover, held there to rest, never over it, nothing over it down" {
  for rate in rc_rates {
    for line in [false, true] {
      let c = fw_case(600.0, line~)
      let more = if line { [fw_key, fw_line] } else { [fw_key] }
      let ys = c.walk(rc_at, fn() {
        c.keys.set(fw_keys(more))
        c.place.follow_from(Some(fw_key), margin=fw_margin)
      }, rate)
      if fw_wrong(ys, fw_cover + fw_margin) is Some(w) {
        fail("at \{rate}, the line \{line}: \{w}")
      }
    }
  }
}

///|
test "follow_from: the margin counts from what covers the list's top; with none, from its top" {
  for rate in rc_rates {
    for cover in [0.0, 80.0] {
      let c = fw_case(600.0, cover~)
      let ys = c.walk(rc_at, fn() {
        c.keys.set(fw_keys([fw_key]))
        c.place.follow_from(Some(fw_key), margin=fw_margin)
      }, rate)
      if fw_wrong(ys, cover + fw_margin) is Some(w) {
        fail("at \{rate}, under \{cover}: \{w}")
      }
    }
  }
}

///|
test "follow_from: held by the key's top, the list is off its foot: a key come after moves nothing that shows; taken to its foot (to_end, the hand), it follows it again" {
  for rate in rc_rates {
    for how in ["to_end", "the hand"] {
      let c = fw_case(600.0)
      let held = c.walk(rc_at, fn() {
        c.keys.set(fw_keys([fw_key]))
        c.place.follow_from(Some(fw_key), margin=fw_margin)
      }, rate)
      let (top, nine, _) = held[held.length() - 1]
      // a key come after: nothing that shows moves
      let at = rc_at + fw_after_ms + 100.0
      let after = c.walk(at, fn() { c.keys.set(fw_keys([fw_key, 71])) }, rate, from=rc_at + fw_after_ms)
      for i, y in after {
        assert_true(
          (y.0 - top).abs() < 0.01 && (y.1 == nine || (y.1 - nine).abs() < 0.01),
          msg="at \{rate}, look \{i}: \{y.0} / \{y.1}, held at \{top} / \{nine}",
        )
      }
      // taken to its foot: there at rest
      let at2 = at + fw_after_ms + 100.0
      let back = c.walk(at2, fn() {
        if how == "to_end" {
          c.place.to_end()
        } else {
          c.scroll.put(c.scroll.most())
        }
      }, rate, from=at + fw_after_ms)
      assert_true(back[back.length() - 1].2 < 0.01, msg="at \{rate}, \{how}: off its foot by \{back[back.length() - 1].2}")
      // and followed again: one more come, at its foot at rest, what was over it gone up
      let at3 = at2 + fw_after_ms + 100.0
      let was = back[back.length() - 1].0
      let again = c.walk(at3, fn() { c.keys.set(fw_keys([fw_key, 71, 72])) }, rate, from=at2 + fw_after_ms)
      let (now, _, off) = again[again.length() - 1]
      assert_true(off < 0.01 && now < was - 39.0, msg="at \{rate}, \{how}: \{was} → \{now}, off its foot by \{off}")
    }
  }
}

///|
test "follow_from: a key that fits rests at the foot, the cap still said; grown past the margin later, held there" {
  for rate in rc_rates {
    let c = fw_case(200.0)
    let fits = c.walk(rc_at, fn() {
      c.keys.set(fw_keys([fw_key]))
      c.place.follow_from(Some(fw_key), margin=fw_margin)
    }, rate)
    let (top, _, off) = fits[fits.length() - 1]
    assert_true(off < 0.01 && top > fw_cover + fw_margin + 1.0, msg="at \{rate}: its top \{top}, off its foot by \{off}")
    let at = rc_at + fw_after_ms + 100.0
    let grown = c.walk(at, fn() { c.tall.set(900.0) }, rate, from=rc_at + fw_after_ms)
    let (top, _, off) = grown[grown.length() - 1]
    assert_true((top - (fw_cover + fw_margin)).abs() < 0.01 && off > 1.0, msg="at \{rate}: grown, its top \{top}, off its foot by \{off}")
  }
}

///|
test "follow_from: the line under it going leaving its room in the same change carries the key's top over the margin none; taking hold within half a point of its foot, it stays held" {
  for rate in rc_rates {
    let c = fw_case(600.0, line=true)
    let ys = c.walk(rc_at, fn() {
      c.keys.set(fw_keys([fw_key]))
      c.place.follow_from(Some(fw_key), margin=fw_margin)
    }, rate)
    if fw_wrong(ys, fw_cover + fw_margin) is Some(w) {
      fail("at \{rate}: \{w}")
    }
    assert_true(!c.scroll.at_foot_now(), msg="at \{rate}: held, at its foot as told")
  }
}


///|
/// The case held by fw_key's top at rest (a key taller than what shows come at rc_at): its last look.
fn fw_held(rate : Double) -> (FwCase, (Double, Double, Double)) {
  let c = fw_case(600.0)
  let ys = c.walk(rc_at, fn() {
    c.keys.set(fw_keys([fw_key]))
    c.place.follow_from(Some(fw_key), margin=fw_margin)
  }, rate)
  (c, ys[ys.length() - 1])
}

///|
test "follow_from: held, the column shrunk so the limit binds no more: at its foot, and following it again" {
  for rate in rc_rates {
    let (c, held) = fw_held(rate)
    assert_true(held.2 > 1.0 && !c.scroll.at_foot_now(), msg="at \{rate}: not held, \{Repr(held)}")
    let at = rc_at + fw_after_ms + 100.0
    let shrunk = c.walk(at, fn() { c.tall.set(100.0) }, rate, from=rc_at + fw_after_ms)
    let (top, _, off) = shrunk[shrunk.length() - 1]
    assert_true(off < 0.01, msg="at \{rate}: shrunk, off its foot by \{off}")
    let at2 = at + fw_after_ms + 100.0
    let next = c.walk(at2, fn() { c.keys.set(fw_keys([fw_key, 71])) }, rate, from=at + fw_after_ms)
    let (now, _, off) = next[next.length() - 1]
    assert_true(off < 0.01 && now < top - 39.0, msg="at \{rate}: \{top} → \{now}, off its foot by \{off}")
  }
}

///|
test "follow_from: held, its key gone: the limit with it, at its foot, the next key followed" {
  for rate in rc_rates {
    let (c, _) = fw_held(rate)
    let at = rc_at + fw_after_ms + 100.0
    let gone = c.walk(at, fn() { c.keys.set(fw_keys([])) }, rate, from=rc_at + fw_after_ms)
    assert_true(gone[gone.length() - 1].2 < 0.01, msg="at \{rate}: gone, off its foot by \{gone[gone.length() - 1].2}")
    let at2 = at + fw_after_ms + 100.0
    let next = c.walk(at2, fn() { c.keys.set(fw_keys([71])) }, rate, from=at + fw_after_ms)
    assert_true(next[next.length() - 1].2 < 0.01, msg="at \{rate}: the next, off its foot by \{next[next.length() - 1].2}")
  }
}
