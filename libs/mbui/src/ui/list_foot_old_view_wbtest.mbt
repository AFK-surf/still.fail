// A page's list whose pinned foot holds an old view (a chat's composer while it is one), laid shorter only as the old
// frame is built (Tree::old_views_built): what it gives back in the change a key comes at the foot in is counted in
// that change, the key's first frame drawn as tall as that, what is over it setting out from rest in the first frame
// drawn after the cause, on one way; no frame drawn with the key at none and the foot shrunk (the coordinator of the
// migration, 2026-11-14: one motion, the composer's closing is the list's rise).

///|
/// The ground of row `k`.
fn foot_old_ink(k : Int) -> Int64 {
  0x40000000L + (k + 10).to_int64() * 0x100L + 0xFFL
}

///|
/// A list 300 by 300 of keys 0 to 29 (20 tall) following its foot, its pinned foot an old view as tall as what it holds
/// (`foot`, 90 at first: the old frame's), key 77 (100 tall). The Tester, the keys, the old view's height.
fn old_foot_case() -> (Tester, @signals.Signal[Array[Int]], @signals.Signal[Double]) {
  let keys = @signals.signal(Array::makei(30, fn(i) { i }), same=fn(a, b) { a == b })
  let foot = @signals.signal(90.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(
        @view.Scroll::list(),
        fn() { keys.get() },
        est=20.0,
        follows=fn() { true },
        foot=fn(f) {
          f.box(fn(b) {
            b.shrink(Is(0.0)) |> ignore
            old(b, fn(c : Ctx) { c.box(w=Fill(1.0), h=Px(foot.get()), fn() {  }) |> ignore }, natural=true) |> ignore
          })
          |> ignore
        },
        fn(b, k) {
          let h = if k == 77 { 100.0 } else { 20.0 }
          b.height(Is(Some(h))).ground(Is(foot_old_ink(k))) |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  (t, keys, foot)
}

///|
/// Where row 29's ground is drawn (its top; -1e9 not), how tall key 77's block shows (its slot as the list draws it, 0
/// none) and the room under the last block (the pinned foot's height as laid).
fn old_foot_look(t : Tester) -> (Double, Double) {
  let y29 = match t.drawn_rects().iter().find_first(fn(r) { r.4 == foot_old_ink(29) }) {
    Some(r) => r.1
    None => -1.0e9
  }
  let key = match view_tree() {
    Some(tree) =>
      match tree.list_in_front() {
        Some(l) =>
          match l.rows.iter().find_first(fn(r) { r.0 == 30 }) {
            Some((_, _, (_, _, _, h))) => h
            None => 0.0
          }
        None => 0.0
      }
    None => 0.0
  }
  (y29, key)
}

///|
test "a pinned foot holding an old view laid shorter only as the old frame is built, closing 90 to 30 in the change a key 100 tall comes in: counted in that change: the key's first frame 60 tall or more, what is over it up from rest in that frame, its first steps each larger, up 40 in all" {
  let (t, keys, foot) = old_foot_case()
  let (y0, _) = old_foot_look(t)
  let seen : Array[(Double, Double, Double)] = []
  t.each_frame(Some(fn() {
    let (y, k) = old_foot_look(t)
    seen.push((t.time(), y, k))
  }))
  let cause = t.time()
  view_event(fn() {
    foot.set(30.0)
    let ks = Array::makei(30, fn(i) { i })
    ks.push(77)
    keys.set(ks)
  })
  t.run_shown(move_most_ms + 100.0)
  t.each_frame(None)
  println("OLDFOOT before \{y0}: \{Repr(seen)}")
  assert_true(seen.length() > 3, msg="\{seen.length()} frames")
  let (_, _, k1) = seen[0]
  assert_true(k1 >= 60.0 - 0.5, msg="the key's first frame \{k1} tall, 60 given back: \{Repr(seen)}")
  for s in seen {
    assert_false(s.2 < 0.5, msg="a frame at \{s.0} with the key at none: \{Repr(seen)}")
  }
  // (from the first frame drawn after the cause: one drawn at its moment shows the way where it sets out)
  let after = seen.filter(fn(s) { s.0 > cause + 0.001 })
  let steps = [y0 - after[0].1, after[0].1 - after[1].1, after[1].1 - after[2].1]
  assert_true(steps[0] > 0.0, msg="what is over it still in the first frame: \{Repr(steps)}, \{Repr(seen)}")
  // (what moves it, the key's growth past what was given back, from rest: each of its first three steps larger; what
  // is over drawn on the half points of the Tester's pixels)
  let k = [60.0, after[0].2, after[1].2, after[2].2]
  let grows = [k[1] - k[0], k[2] - k[1], k[3] - k[2]]
  assert_true(grows[0] > 0.0 && grows[1] > grows[0] && grows[2] > grows[1], msg="its first steps not from rest: \{Repr(grows)}")
  let (y_end, _) = old_foot_look(t)
  assert_true((y0 - y_end - 40.0).abs() < 0.5, msg="up \{y0 - y_end}, 40 wanted")
}

