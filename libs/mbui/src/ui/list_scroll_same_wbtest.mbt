// A page's list on the window's tree (View::scrolls with a scroll made as a list's: Scroll::list) against an old view's
// list (Ctx::list), each the window's whole, as tall all through, the same hand on each on each platform: where it is
// and how far it shows past its end, and its rows as drawn (stretched on Android, moved on iOS's rubber band), frame by
// frame, the same: flung (short of its end), pulled past its top and let go, the wheel turned on it as that goes back,
// the wheel's notches eased in. Not flung into its end: an old view's list finds its end at the frame after it got
// there, the tree's where it gets there (scroll_list_wbtest.mbt). Each row a box with round corners cutting what it holds (a box with its own round corners taller
// than it, its words): what is drawn of it, cut, stretched and moved, the same.

///|
/// How long after what was pulled past its top is let go the wheel comes on it: on its way back by then.
let same_back_ms : Double = 50.0

///|
/// How far apart a wheel's notches come, one easing in as the next comes; and how long after them their ease is over.
let same_notch_ms : Double = 30.0

///|
let same_eased_ms : Double = 400.0

///|
/// The words of row `i`.
fn same_words(i : Int) -> String {
  "row \{i}"
}

///|
/// An old view's list of `n` rows 50 high, the window's whole (scroll_wbtest's rows_view).
fn same_old(n : Int, platform : Int) -> Tester {
  Tester::new(
    fn(c) {
      c.list("l", n, 50.0, fn(i) {
        c.box(h=Px(50.0), bg=0xEEEEEEFFL, radius=12.0, clip=true, dir=Row, fn() {
          c.box(w=Px(40.0), h=Px(80.0), bg=0x3366CCFFL, radius=8.0, fn() {  }) |> ignore
          c.text(same_words(i), size=13.0, line=18.0) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    platform~,
  )
}

///|
/// A column of the window's tree scrolling as a page's list, the window's whole, holding `n` rows 50 high as same_old's,
/// under as much as `above` says of nothing and over as much as `below` says, with its bar where `bar` says, there while `shown` says: its scroll.
fn same_tree(
  n : Int,
  platform : Int,
  pointing? : Pointing,
  bar? : Bool = false,
  shown? : @signals.Signal[Bool] = @signals.signal(true),
  above? : @signals.Signal[Double] = @signals.signal(0.0),
  below? : @signals.Signal[Double] = @signals.signal(0.0),
) -> (Tester, @view.Scroll) {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, platform~, pointing?)
  set_view_app(fn(root) {
    root.show(at_once=true, fn() { shown.get() }, fn(col) {
      col
      .width(Is(Some(390.0)))
      .height(Is(Some(844.0)))
      .scrolls(s, bar?=if bar { Some(tree_scroll_bar()) } else { None }, fn(body) {
        body.box(fn(gap) { gap.height(By(fn() { Some(above.get()) })) |> ignore }) |> ignore
        for i in 0..<n {
          body.box(fn(row) {
            row.height(Is(Some(50.0))).ground(Is(0xEEEEEEFFL)).radius(Is(12.0)).clips(Is(true)).row(Is(true)) |> ignore
            row.box(fn(b) { b.width(Is(Some(40.0))).height(Is(Some(80.0))).ground(Is(0x3366CCFFL)).radius(Is(8.0)) |> ignore })
            |> ignore
            row.box(fn(w) {
              w
              .words(Is(same_words(i)), look={ size: 13.0, weight: 400, line: 18.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
              .ink(By(fn() { tree_theme().color(Fg) }))
              |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        body.box(fn(gap) { gap.height(By(fn() { Some(below.get()) })) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, s)
}

///|
/// How far an old view's list shows past its end, as the tree's says it (Scroll::past): Android's stretch in its
/// heights, iOS's rubber band in the points it shows moved, from the top positive.
fn old_past(t : Tester, platform : Int) -> Double {
  let st = t.list_state()
  match platform {
    1 => st.over_offset()
    2 => st.over * st.over_edge.to_double()
    _ => 0.0
  }
}

///|
/// The hand of each way it is tried (on the tester given): flung short of its end, pulled past its top and let go,
/// flung into its end; and how many rows it is tried on.
fn same_ways() -> Array[(String, Int, (Tester) -> Unit)] {
  [
    ("flung", 100, fn(t) { swipe(t, 700.0, -10.0, 6) }),
    (
      "pulled past its top, let go",
      100,
      fn(t) {
        t.touch(0, 200.0, 300.0)
        for k in 1..=10 {
          t.advance(drag_step_ms)
          t.touch(1, 200.0, 300.0 + 10.0 * k.to_double())
          t.draw()
        }
        t.advance(tracker_horizon_ms)
        t.touch(2, 200.0, 400.0)
      },
    ),
    (
      "pulled past its top, let go, the wheel turned as it goes back",
      100,
      fn(t) {
        t.touch(0, 200.0, 300.0)
        for k in 1..=10 {
          t.advance(drag_step_ms)
          t.touch(1, 200.0, 300.0 + 10.0 * k.to_double())
          t.draw()
        }
        t.advance(tracker_horizon_ms)
        t.touch(2, 200.0, 400.0)
        t.draw()
        t.advance(same_back_ms)
        t.wheel(200.0, 400.0, 30.0)
      },
    ),
    (
      "pulled past its top, let go, a short notch of the wheel turned as it goes back",
      100,
      fn(t) {
        t.touch(0, 200.0, 300.0)
        for k in 1..=10 {
          t.advance(drag_step_ms)
          t.touch(1, 200.0, 300.0 + 10.0 * k.to_double())
          t.draw()
        }
        t.advance(tracker_horizon_ms)
        t.touch(2, 200.0, 400.0)
        t.draw()
        t.advance(same_back_ms)
        t.draw()
        // (a notch of 2: eased in well before what is past the top is back)
        t.wheel_phase(200.0, 400.0, 2.0, 4)
      },
    ),
    (
      "the wheel's notches, one on another, then up past its top",
      100,
      fn(t) {
        for k in 0..<3 {
          t.wheel_phase(200.0, 400.0, 40.0, 4)
          t.advance(same_notch_ms + 10.0 * k.to_double())
          t.draw()
        }
        t.advance(same_eased_ms)
        t.draw()
        t.wheel_phase(200.0, 400.0, -100.0, 4)
        t.advance(same_notch_ms)
        t.draw()
        t.wheel_phase(200.0, 400.0, -100.0, 4)
      },
    ),
  ]
}

///|
/// What of its rows is drawn in the window: each box and glyph seen, where (x, y, w, h), its corners, the clip it is cut
/// to (top and foot, its outer clip's as well where it has one), its colour and how tall what shows of it is, in the
/// order of where.
fn same_drawn(t : Tester) -> Array[Array[Double]] {
  let out = []
  for a in t.drawn_instances() {
    let kind = a[5]
    let ink = ((a[8] * 255.0).round().to_int64() << 24) |
      ((a[9] * 255.0).round().to_int64() << 16) |
      ((a[10] * 255.0).round().to_int64() << 8) |
      (a[11] * 255.0).round().to_int64()
    let ours = kind == 1.0 || (kind == 0.0 && (ink == 0xEEEEEEFFL || ink == 0x3366CCFFL))
    // (seen: within the window, its clip and its outer clip where it has one, 40-43: a page's list's rows past the
    // window cut by its header's clip there, view_ride.mbt's inst_cut_to)
    let outer = a[40] != 0.0 || a[41] != 0.0 || a[42] != 0.0 || a[43] != 0.0
    let cut_top = if outer { dmax(a[17], a[41]) } else { a[17] }
    let cut_foot = if outer { dmin(a[19], a[43]) } else { a[19] }
    // (and how tall what shows of it is, last)
    let seen = dmin(dmin(a[1] + a[3], cut_foot), 844.0) - dmax(dmax(a[1], cut_top), 0.0)
    if ours && seen > 0.0 {
      out.push([kind, a[0], a[1], a[2], a[3], a[4], cut_top, cut_foot, ink.to_double(), seen])
    }
  }
  out.sort_by(fn(p, q) {
    if p[2] != q[2] {
      p[2].compare(q[2])
    } else if p[1] != q[1] {
      p[1].compare(q[1])
    } else {
      p[0].compare(q[0])
    }
  })
  out
}

///|
/// Each frame of the display's for 3 s from the hand let go: when, where it is and how far it shows past its end; and
/// where its rows are drawn in the window, top and height each.
fn same_frames(t : Tester, at : () -> (Double, Double)) -> (Array[(Double, Double, Double)], Array[Array[Array[Double]]]) {
  let out = []
  let rows = []
  let end = t.time() + 3000.0
  t.draw()
  while t.time() < end {
    let (x, past) = at()
    out.push((t.time(), x, past))
    rows.push(same_drawn(t))
    t.frame()
  }
  (out, rows)
}

///|
test "a page's list on the window's tree moves as an old view's list, frame by frame, on each platform" {
  let differ = []
  for platform in [0, 1, 2] {
    for way in same_ways() {
      let (name, n, hand) = way
      let old = same_old(n, platform)
      hand(old)
      let (was, was_rows) = same_frames(old, fn() { (old.list_offset(), old_past(old, platform)) })
      let (t, s) = same_tree(n, platform)
      hand(t)
      let tree = view_tree().unwrap()
      let (now, now_rows) = same_frames(t, fn() { (s.at(tree), s.past(tree)) })
      let past_same = fn(a : Double, b : Double) { (a - b).abs() <= 1.0e-6 }
      // (where it is as it is drawn: the tree's list moved by whole pixels of the Tester's (2 to a point:
      // Scroll::held_dy), an old view's list's boxes where it is, not set on them (rows_on_pixels, said by no fake
      // host), so within half a device pixel of each other each frame; and the same at last. A wheel's notch on the
      // tree's ends at the moment it is drawn where it comes to (Scroll::ease_drawn_end), the old view's eases on
      // under that half a pixel: the same as drawn, not as numbers)
      let drawn = fn(x : Double) { (x * 2.0).round() / 2.0 }
      let k = (0).until(imin(was.length(), now.length())).find_first(fn(k) {
        let (a, b) = (was[k], now[k])
        let at_same = if k == was.length() - 1 {
          (a.1 - b.1).abs() <= 1.0e-6
        } else {
          (a.1 - drawn(b.1)).abs() <= 0.25
        }
        a.0 != b.0 || !at_same || !past_same(a.2, b.2)
      })
      // (past an end it went, where its platform's does: else this tells nothing of it)
      let most = was.fold(init=0.0, fn(m, f) { dmax(m, f.2.abs()) })
      // (and seen so: as much drawn of it in each)
      if was_rows.iter().all(fn(f) { f.length() == 0 }) {
        differ.push("\{platform} \{name}: nothing of its rows drawn")
      }
      if platform != 0 && name != "flung" && !name.has_prefix("the wheel's notches") && most < 0.01 {
        differ.push("\{platform} \{name}: the old view's list shows nothing past its end")
      }
      match k {
        Some(k) => differ.push("\{platform} \{name}: at \{k} old \{Repr(was[k])} tree \{Repr(now[k])}; last old \{Repr(was.last())} tree \{Repr(now.last())}")
        None => if was.length() != now.length() { differ.push("\{platform} \{name}: \{was.length()} frames, \{now.length()}") }
      }
      // (its rows as drawn, the first frame they differ at)
      // (where each is, how big as stretched and what cuts it, up to a pixel of the Tester's (scale 2; as Android stretches
      // it, a fifth more at most): the tree's list moved by whole pixels as it is drawn once and moved (Scroll::held_dy),
      // an old view's boxes off by part of one and its words each set on one as they came, the rest the same; so what
      // shows of one at an edge by less than three of them may show in one, not the other: each that shows by more found
      // in the other)
      let alike = fn(a : Array[Double], b : Array[Double]) {
        (0).until(9).iter().all(fn(i) {
          let most = if (i >= 1 && i <= 4) || i == 6 || i == 7 { 0.6 } else { 1.0e-3 }
          (a[i] - b[i]).abs() <= most
        })
      }
      let lost = fn(a : Array[Array[Double]], b : Array[Array[Double]]) {
        a.iter().find_first(fn(e) { e[9] >= 1.5 && !b.iter().any(fn(f) { alike(e, f) }) })
      }
      let r = (0).until(imin(was_rows.length(), now_rows.length())).find_first(fn(k) {
        let (a, b) = (was_rows[k], now_rows[k])
        lost(a, b) is Some(_) || lost(b, a) is Some(_)
      })
      if r is Some(r) {
        let (a, b) = (was_rows[r], now_rows[r])
        differ.push(
          "\{platform} \{name}: drawn at \{r} (\{was[r].0}): old \{a.length()}, tree \{b.length()}; the old's not in the tree's \{Repr(lost(a, b))}, the tree's not in the old's \{Repr(lost(b, a))}",
        )
      }
    }
  }
  if differ.length() > 0 {
    fail(differ.join("\n"))
  }
}
