// A page's list's key said to come whole (View::scrolls_window's `comes_whole`), as the paint draws it: while it makes
// its way at the list's foot, what its block draws is moved to after all the list draws (its pinned foot's ground, a
// key under it), cut as where it is (by where the list shows, nothing of its room), at full ink; at rest, and an
// unmarked key all along, in the tree's order (under the foot) (the coordinator of the migration, 2026-11-14).

///|
/// The ground of row `k`, of the key that comes, and of the foot.
fn whole_ink(k : Int) -> Int64 {
  0x40000000L + (k + 10).to_int64() * 0x100L + 0xFFL
}

///|
let whole_key_ink : Int64 = 0x204060FFL

///|
let whole_foot_ink : Int64 = 0x40FFFFFFL

///|
/// A list 300 by 300 of keys 0 to 29 (20 tall) following its foot, a foot 60 tall (its ground drawn), key 77 (50 tall, a
/// ground 200 wide; 78 the same, 180 wide) said to come whole where `marked`; a line 30 (24 tall) under the keys
/// where `under` (77 comes over it). The Tester and the keys.
fn whole_case(marked : Bool, under? : Bool = false) -> (Tester, @signals.Signal[Array[Int]]) {
  let first = Array::makei(30, fn(i) { i })
  if under {
    first.push(30)
  }
  let keys = @signals.signal(first, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(
        @view.Scroll::list(),
        fn() { keys.get() },
        est=20.0,
        follows=fn() { true },
        comes_whole=fn(k) { marked && (k == 77 || k == 78) },
        foot=fn(f) {
          f.box(fn(b) { b.height(Is(Some(60.0))).shrink(Is(0.0)).ground(Is(whole_foot_ink)) |> ignore }) |> ignore
        },
        fn(b, k) {
          if k == 77 || k == 78 {
            b.box(fn(i) {
              i.width(Is(Some(if k == 77 { 200.0 } else { 180.0 }))).height(Is(Some(50.0))).shrink(Is(0.0)).ground(Is(whole_key_ink))
              |> ignore
            })
            |> ignore
          } else if k == 30 {
            b.height(Is(Some(24.0))).ground(Is(whole_ink(k))) |> ignore
          } else {
            b.height(Is(Some(20.0))).ground(Is(whole_ink(k))) |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, keys)
}

///|
/// What one frame draws of it: where among the instances the key's ground, the foot's and the line's are (-1: not
/// drawn; `key2` the second marked key's, 78's), the key's ground as drawn (y, h, opacity) and the rect it is cut to
/// (y0, y1).
priv struct WholeFrame {
  at : Double
  key : Int
  key2 : Int
  foot : Int
  line : Int
  y : Double
  h : Double
  a : Double
  cut : (Double, Double)
  raised : Int
}

///|
fn whole_frame(t : Tester) -> WholeFrame {
  let order = t.drawn_order()
  let cuts = t.drawn_cut()
  let raised = match view_tree() {
    Some(tree) => tree.raised_blocks().length()
    None => 0
  }
  let mut f : WholeFrame = { at: t.time(), key: -1, key2: -1, foot: -1, line: -1, y: 0.0, h: 0.0, a: 0.0, cut: (0.0, 0.0), raised }
  for i, o in order {
    let (kind, _, y, w, h, a) = o
    guard kind == 0 else { continue }
    if (w - 200.0).abs() < 0.01 && (h - 50.0).abs() < 0.01 {
      let (_, _, _, _, _, (_, y0, _, y1)) = cuts[i]
      f = { ..f, key: i, y, h, a, cut: (y0, y1) }
    } else if (w - 180.0).abs() < 0.01 && (h - 50.0).abs() < 0.01 {
      f = { ..f, key2: i }
    } else if (w - 300.0).abs() < 0.01 && (h - 60.0).abs() < 0.01 {
      f = { ..f, foot: i }
    } else if (w - 300.0).abs() < 0.01 && (h - 24.0).abs() < 0.01 {
      f = { ..f, line: i }
    }
  }
  f
}

///|
/// The case's key brought in by data (over the line where there is one), every frame drawn from there till it rests.
fn whole_walk(marked : Bool, under? : Bool = false) -> Array[WholeFrame] {
  let (t, keys) = whole_case(marked, under~)
  let frames = []
  t.each_frame(Some(fn() { frames.push(whole_frame(t)) }))
  view_event(fn() {
    let ks = Array::makei(30, fn(i) { i })
    ks.push(77)
    if under {
      ks.push(30)
    }
    keys.set(ks)
  })
  t.run_shown(move_most_ms + 100.0)
  t.each_frame(None)
  frames.push(whole_frame(t))
  frames
}

///|
test "a key said to come whole at the foot: on its way drawn after the pinned foot's ground, at full ink, its ground whole (cut only by where the list shows); at rest in the tree's order under the foot; an unmarked key under the foot all along" {
  let frames = whole_walk(true)
  let rest = frames[frames.length() - 1]
  let mut over = 0
  for f in frames[:frames.length() - 1] {
    guard f.key >= 0 && f.raised > 0 else { continue }
    assert_true(f.key > f.foot, msg="at \{f.at}: the key's ground drawn at \{f.key}, the foot's at \{f.foot}")
    assert_true((f.a - 1.0).abs() < 0.01, msg="at \{f.at}: drawn at \{f.a}")
    let foot = if f.y + f.h < 300.0 { f.y + f.h } else { 300.0 }
    assert_true(f.cut.0 <= f.y + 0.01 && f.cut.1 >= foot - 0.01, msg="at \{f.at}: drawn \{f.y}..\{f.y + f.h}, cut to \{Repr(f.cut)}")
    over += 1
  }
  assert_true(over > 0, msg="never drawn on its way: \{frames.length()} frames")
  assert_eq(rest.raised, 0, msg="raised at rest")
  assert_true(rest.key >= 0 && rest.key < rest.foot, msg="at rest: the key's ground at \{rest.key}, the foot's at \{rest.foot}")
  // (unmarked: under the foot in every frame it is drawn)
  for f in whole_walk(false) {
    if f.key >= 0 {
      assert_true(f.key < f.foot, msg="unmarked, at \{f.at}: the key's ground at \{f.key}, the foot's at \{f.foot}")
    }
  }
}

///|
test "a key said to come whole over a line that stays under it: on its way drawn after the line and the foot" {
  let frames = whole_walk(true, under=true)
  let mut over = 0
  for f in frames[:frames.length() - 1] {
    guard f.key >= 0 && f.line >= 0 && f.raised > 0 else { continue }
    assert_true(f.key > f.line && f.key > f.foot, msg="at \{f.at}: the key at \{f.key}, the line at \{f.line}, the foot at \{f.foot}")
    over += 1
  }
  assert_true(over > 0, msg="never drawn with the line")
}


///|
/// Two marked keys brought in by data 100 ms apart (77, then 78 after it, both over the line where there is one), the
/// first still on its way as the second comes: every frame from the first till both rest.
fn whole_walk_two(under : Bool) -> Array[WholeFrame] {
  let (t, keys) = whole_case(true, under~)
  let frames = []
  let keys_of = fn(more : Array[Int]) {
    let ks = Array::makei(30, fn(i) { i })
    ks.append(more)
    if under {
      ks.push(30)
    }
    ks
  }
  t.each_frame(Some(fn() { frames.push(whole_frame(t)) }))
  view_event(fn() { keys.set(keys_of([77])) })
  t.run_shown(100.0)
  view_event(fn() { keys.set(keys_of([77, 78])) })
  t.run_shown(move_most_ms + 100.0)
  t.each_frame(None)
  frames.push(whole_frame(t))
  frames
}

///|
test "two keys said to come whole on their way at once (the second come as the first still goes): both drawn after the pinned foot's ground, in their order; over a line that stays under them, after the line too" {
  for under in [false, true] {
    let frames = whole_walk_two(under)
    let mut both = 0
    for f in frames[:frames.length() - 1] {
      guard f.key >= 0 && f.key2 >= 0 && f.raised == 2 else { continue }
      assert_true(f.key > f.foot && f.key2 > f.foot && f.key < f.key2, msg="under \{under}, at \{f.at}: 77 at \{f.key}, 78 at \{f.key2}, the foot at \{f.foot}")
      if under {
        assert_true(f.key > f.line, msg="at \{f.at}: 77 at \{f.key}, the line at \{f.line}")
      }
      both += 1
    }
    assert_true(both > 0, msg="under \{under}: never both raised: \{frames.length()} frames")
    let rest = frames[frames.length() - 1]
    assert_eq(rest.raised, 0, msg="under \{under}: raised at rest")
  }
}
