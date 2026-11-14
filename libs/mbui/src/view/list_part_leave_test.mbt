// A guard (it passes on main, as the framework is): a small part of a block of a page's list said to leave (a pick said
// `leave`, pick_leave.mbt: what it showed fades where it is, its place closing once that is gone; coming, its place
// first, then seen), the list at its foot and following it: a line of words under the last block's words going and
// then coming back, no key coming. No glyph drawn cut at any look: each wholly inside what is drawn of it or not drawn
// at all, the one edge that may cross words the pinned foot's top; and what is over it moves along its way, never by a
// step (its place is never let go or made at once). Looked at every 10 ms, in one jump and at 60, 120, 24 and 7 a
// second (rc_walk). A show said `leave` is not this: it holds its place while it leaves and lets it go at once.

///|
/// The rows (0 to 9, 40 each, then 70: its words 40 and, under them, its part 22, words 部, a pick of whether it shows said to leave over `leave`),
/// the foot 30 pinned under them; drawn once, at 0.
fn pl_case(leave : Double) -> (@view.Tree, @signals.Signal[Bool], Ref[@view.View?]) {
  let keys = @signals.signal(rc_ten_and([70]), same=fn(a, b) { a == b })
  let part = @signals.signal(true, same=fn(a, b) { a == b })
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
        foot=fn(f) {
          f.box(fn(b) {
            b.height(Is(Some(30.0))).shrink(Is(0.0)) |> ignore
            foot_box.val = Some(b)
          })
          |> ignore
        },
        fn(b, k) {
          if k == 70 {
            b.box(fn(w) { w.height(Is(Some(40.0))).shrink(Is(0.0)).words(Is("行70")) |> ignore }) |> ignore
            b.pick(fn() { part.get() }, leave~, fn(p, on) {
              if on {
                p.box(fn(w) { w.height(Is(Some(22.0))).shrink(Is(0.0)).words(Is("部")) |> ignore }) |> ignore
              }
            })
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
  (tree, part, foot_box)
}

///|
/// The most what is over the part may move between two looks 10 ms apart: a Move of 22 points goes no faster (its
/// height at once, 22, is the fault).
let pl_step_most : Double = 6.0

///|
test "guard: a page's list at its foot, the last block's line of words a pick said to leave, going and coming back, no key coming: no glyph drawn cut at any look (but at the pinned foot's top), what is over it never stepping, at every rate" {
  let back_at = rc_at + 1000.0
  let looks = rc_looks(back_at + 1000.0)
  for leave in [150.0] {
    for rate in rc_rates {
      let (t, part, foot_box) = pl_case(leave)
      let seen = rc_walk(t, [(rc_at, fn() { part.set(false) }), (back_at, fn() { part.set(true) })], looks, rate, fn() {
        let foot_top = match foot_box.val {
          Some(b) => b.placed_window_now().1
          None => 370.0
        }
        (om_cut(t, ["行70", "部", "行9"], foot_top), om_seen(t, "部"), rc_y(t, "行70"))
      })
      let at = "leave \{leave}, at \{rate} a second"
      for i, s in seen {
        match s.0 {
          Some(w) => fail("\{at}, look \{i} (\{looks[i]}): \{w}")
          None => ()
        }
        // (its place making its way: what is over it a little further each look, never its height at once)
        if i > 0 {
          let step = (s.2 - seen[i - 1].2).abs()
          assert_true(step < pl_step_most, msg="\{at}, look \{i} (\{looks[i]}): 行70 moved \{step} at once")
        }
      }
      // (gone between, and back at rest)
      assert_true(seen.iter().any(fn(s) { !s.1 }), msg="\{at}: the part never gone")
      assert_true(seen[seen.length() - 1].1, msg="\{at}: the part not back at rest")
    }
  }
}
