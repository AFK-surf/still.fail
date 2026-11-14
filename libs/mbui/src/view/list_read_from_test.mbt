// What is read in a page's list stays where it is on the screen in every frame (the owner's principle: what the reader
// has before their eyes does not move): its block marks where its words start (View::read_from), under the room over it
// and the head line, and the list holds the first key whose start so marked is under what covers its top by where that
// start is (list_read_from.mbt). So as the key over it grows, as a part over it closes or opens on a way, as keys come
// before it (out of sight or in sight over it), as the room over its own words changes at once and on a way, as the
// width changes, and as it grows itself, its words do not move, its rows on a host's pixels too (Tree::set_rows_grid,
// within half a pixel); a list that marks none is held by its top as before.
// Each looked at at moments it declares, drawn in one jump and at 60, 120, 24 and 7 a second (rc_walk, rc_rates).

///|
/// What covers the list's top (a page's bar), and where the list is put: block 9's top at the top of what shows, its
/// words starting at 32 (under the cover), block 10's at 104 (in sight): 10 is what is read.
let rf_cover : Double = 50.0

///|
let rf_at : Double = 648.0

///|
/// What a block holds, top to bottom: the room over it (bound, 16; and a pick of none or 12), its head line (16), its
/// words (40, or as the scene says), a part under them (a show, 100 open).
let rf_gap : Double = 16.0

///|
let rf_gap_more : Double = 12.0

///|
let rf_head : Double = 16.0

///|
let rf_words : Double = 40.0

///|
let rf_part : Double = 100.0

///|
/// Each block's own state, by its key: how tall its words are, the bound room over it, whether the picked room over it
/// is there, whether its part is open.
priv struct RfKey {
  words : @signals.Signal[Double]
  gap : @signals.Signal[Double]
  gap_more : @signals.Signal[Bool]
  part : @signals.Signal[Bool]
}

///|
priv struct RfCase {
  tree : @view.Tree
  keys : @signals.Signal[Array[Int]]
  width : @signals.Signal[Double]
  of : (Int) -> RfKey
}

///|
/// A page's list `width` by 300 of 30 keys under a cover of rf_cover, each block as above, its words marked where
/// `marked`; `by_width`: its words as much taller as it is narrower than 300 and the room over them 8 under 280. Put at
/// rf_at at 1, drawn at 2.
fn rf_case(
  marked? : Bool = true,
  by_width? : Bool = false,
  parts_open? : Array[Int] = [],
  grid? : Double = 0.0,
) -> RfCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(30, fn(i) { i }), same=fn(a, b) { a == b })
  let width = @signals.signal(300.0, same=fn(a, b) { a == b })
  let states : Map[Int, RfKey] = Map([])
  let of = fn(k : Int) -> RfKey {
    match states.get(k) {
      Some(st) => st
      None => {
        let st = {
          words: @signals.signal(rf_words, same=fn(a, b) { a == b }),
          gap: @signals.signal(rf_gap, same=fn(a, b) { a == b }),
          gap_more: @signals.signal(false, same=fn(a, b) { a == b }),
          part: @signals.signal(parts_open.contains(k), same=fn(a, b) { a == b }),
        }
        states[k] = st
        st
      }
    }
  }
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(By(fn() { Some(width.get()) })).height(Is(Some(300.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=72.0, top_covered=fn() { rf_cover }, fn(b, k) {
        let st = of(k)
        b.box(fn(g) {
          g.height(
            By(fn() {
              Some(if by_width && width.get() < 280.0 { rf_gap / 2.0 } else { st.gap.get() })
            }),
          )
          |> ignore
        })
        |> ignore
        b.pick(fn() { st.gap_more.get() }, fn(g, on) {
          g.height(Is(Some(if on { rf_gap_more } else { 0.0 }))) |> ignore
        })
        b.box(fn(h) { h.height(Is(Some(rf_head))).words(Is("名\{k}")) |> ignore }) |> ignore
        b.box(fn(w) {
          w.height(
            By(fn() {
              Some(if by_width { st.words.get() * 300.0 / width.get() } else { st.words.get() })
            }),
          ).words(Is("行\{k}"))
          |> ignore
          if marked {
            w.read_from() |> ignore
          }
        })
        |> ignore
        b.show(fn() { st.part.get() }, fn(p) { p.height(Is(Some(rf_part))).words(Is("件\{k}")) |> ignore })
      })
      |> ignore
    })
    |> ignore
  })
  if grid > 0.0 {
    tree.set_rows_grid(grid)
  }
  tree.frame(390.0, 844.0) |> ignore
  tree.event(1.0, fn() { scroll.put(rf_at) })
  tree.at(2.0)
  tree.frame(390.0, 844.0) |> ignore
  { tree, keys, width, of }
}

///|
/// Where `words` are drawn at each look from rc_at to 600 past it, `cause` done at rc_at, at `rate`; and before it.
fn rf_walk(c : RfCase, words : String, cause : () -> Unit, rate : Double) -> (Double, Array[Double]) {
  let was = rc_y(c.tree, words)
  let ys = rc_walk(c.tree, [(rc_at, cause)], rc_looks(rc_at + 600.0), rate, from=2.0, fn() { rc_y(c.tree, words) })
  (was, ys)
}

///|
/// Whether `ys` all lie within half a device pixel (`still`: a quarter of a point, two pixels a point) of `was`; else
/// the first that does not.
fn rf_held(was : Double, ys : Array[Double], still? : Double = 0.25) -> String? {
  for i, y in ys {
    if (y - was).abs() > still {
      return Some("at look \{i} (\{rc_at + i.to_double() * rc_look_ms} ms) at \{y}, was \{was}")
    }
  }
  None
}

///|
/// Fails, saying `what` and the first look off where `ys` is not all held at `was` (rf_held).
fn rf_assert(was : Double, ys : Array[Double], what : String, still? : Double = 0.25) -> Unit raise {
  match rf_held(was, ys, still~) {
    Some(m) => fail("\{what}: \{m}")
    None => ()
  }
}

///|
test "a page's list held by what is read: 行10's words where they start under the cover, the key over it told longer at once; held there in every frame, at every rate" {
  for rate in rc_rates {
    let c = rf_case()
    assert_eq(rc_y(c.tree, "行10"), 72.0 + rf_gap + rf_head, msg="put where the scene says")
    let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(9).words.set(80.0) }, rate)
    rf_assert(was, ys, "at \{rate} a second")
  }
}

///|
test "a page's list held by what is read: the part over 行10's words closing on a way, then one opening; held there in every frame, at every rate" {
  for rate in rc_rates {
    let c = rf_case(parts_open=[9])
    let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(9).part.set(false) }, rate)
    rf_assert(was, ys, "closing, at \{rate} a second")
    let c = rf_case()
    let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(9).part.set(true) }, rate)
    rf_assert(was, ys, "opening, at \{rate} a second")
  }
}

///|
test "a page's list held by what is read: keys come before 行10, out of sight and in sight over it on their way; held there in every frame, at every rate" {
  for rate in rc_rates {
    let c = rf_case()
    let (was, ys) = rf_walk(
      c,
      "行10",
      fn() {
        let ks = [-3, -2, -1]
        ks.append(Array::makei(30, fn(i) { i }))
        c.keys.set(ks)
      },
      rate,
    )
    rf_assert(was, ys, "out of sight, at \{rate} a second")
    let c = rf_case()
    let (was, ys) = rf_walk(
      c,
      "行10",
      fn() {
        let ks = Array::makei(10, fn(i) { i })
        ks.push(100)
        ks.append(Array::makei(20, fn(i) { i + 10 }))
        c.keys.set(ks)
      },
      rate,
    )
    rf_assert(was, ys, "in sight over it, at \{rate} a second")
  }
}

///|
test "a page's list held by what is read: the room over 行10's own words changed at once, and on a way; held there in every frame, at every rate" {
  for rate in rc_rates {
    let c = rf_case()
    let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(10).gap.set(4.0) }, rate)
    rf_assert(was, ys, "at once, at \{rate} a second")
    let c = rf_case()
    let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(10).gap_more.set(true) }, rate)
    rf_assert(was, ys, "on a way, at \{rate} a second")
  }
}

///|
test "a page's list held by what is read: the list narrower, the words over 行10 taller and the room over its own words less; held there in every frame, at every rate" {
  for rate in rc_rates {
    let c = rf_case(by_width=true)
    let (was, ys) = rf_walk(c, "行10", fn() { c.width.set(250.0) }, rate)
    rf_assert(was, ys, "at \{rate} a second")
  }
}

///|
test "a page's list held by what is read: 行10 told longer itself goes down from where its words start, they stay; at every rate" {
  for rate in rc_rates {
    let c = rf_case()
    let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(10).words.set(80.0) }, rate)
    rf_assert(was, ys, "at \{rate} a second")
  }
}

///|
test "a page's list none of whose blocks marks where it is read: held by the block the top of what shows lies in, by its top, as before (行10 down as far as the key over it grew), at every rate" {
  for rate in rc_rates {
    let c = rf_case(marked=false)
    let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(9).words.set(80.0) }, rate)
    for i, y in ys {
      assert_true((y - (was + 40.0)).abs() < 0.001, msg="at \{rate} a second, look \{i}: at \{y}, was \{was}")
    }
  }
}

///|
test "a page's list held by what is read, its rows on a host's pixels (2 and 3 a point): the key over 行10 told longer, the part over it closing on a way; held where it is drawn, within half a pixel, at every rate" {
  for grid in [2.0, 3.0] {
    for rate in rc_rates {
      let c = rf_case(grid~)
      let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(9).words.set(80.3) }, rate)
      rf_assert(was, ys, "told longer, \{grid} a point, at \{rate} a second", still=0.5 / grid)
      let c = rf_case(grid~, parts_open=[9])
      let (was, ys) = rf_walk(c, "行10", fn() { (c.of)(9).part.set(false) }, rate)
      rf_assert(was, ys, "closing, \{grid} a point, at \{rate} a second", still=0.5 / grid)
    }
  }
}
