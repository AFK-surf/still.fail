// A change of state moved to (move_state.mbt), and what CSS says of a box that the flex engine lays out anyway
// (margins, a share of the parent's, a place in it).

///|
/// How long the dock's move takes: a Move as long as the furthest of it goes (its width, 300 to 56).
let dock_ms : Double = move_ms(300.0 - 56.0)

///|
/// A dock that folds (the web's sidebar block, shell.css.ts dock): 300 wide, flush, square and on the page's ground
/// open; 56 wide, 6 in, rounded and on a panel's ground folded. `fold` set: the view folds or opens it as it builds,
/// moving `props` (all of them by default) on a Move as long as the furthest of them goes. Its node, each frame.
priv struct Dock {
  folded : Ref[Bool]
  fold : Ref[Bool]
  node : Ref[Int]
  page : Ref[Int]
}

///|
fn Dock::new() -> Dock {
  { folded: Ref(false), fold: Ref(false), node: Ref(-1), page: Ref(-1) }
}

///|
fn Dock::view(
  self : Dock,
  props? : Array[String] = ["width", "margin", "border-radius", "background-color"],
) -> (Ctx) -> Unit {
  fn(c) {
    if self.fold.val {
      self.fold.val = false
      c.move_state([("dock", props), ("page", ["margin-left"])])
      self.folded.val = !self.folded.val
    }
    let f = self.folded.val
    c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
      self.node.val = c.box(
        moves="dock",
        w=Px(if f { 56.0 } else { 300.0 }),
        h=Fill(1.0),
        m=if f { 6.0 } else { 0.0 },
        radius=if f { 15.0 } else { 0.0 },
        bg=if f { 0xFFFFFFFFL } else { 0xF4F1EAFFL },
        fn() {  },
      )
      // the page beside it, moved aside as far as the dock reaches (not laid out anew by its own move)
      self.page.val = c.box(moves="page", w=Fill(1.0), h=Fill(1.0), ml=if f { 8.0 } else { 0.0 }, fn() {  })
    })
    |> ignore
  }
}

///|
fn width_of(i : Int) -> Double {
  g().node_rect(i).2
}

///|
test "a state moved to: each property from what it showed to what is built, on the web's clock and curve" {
  let d = Dock::new()
  let t = Tester::new(d.view(), w=800.0, h=600.0)
  t.draw()
  assert_eq(width_of(d.node.val), 300.0)
  d.fold.val = true
  t.draw()
  // as it sets out: what it showed, the change not seen at once
  let start = t.time()
  assert_eq(width_of(d.node.val), 300.0)
  // half its time in: a Move's way at a half, of each property
  // (its time in whole ms, as a motion's goes)
  let half = (dock_ms / 2.0).floor()
  t.run_for(half)
  let p = Ease::Move.at(half / dock_ms)
  let w = 300.0 + (56.0 - 300.0) * p
  assert_true((width_of(d.node.val) - w).abs() < 0.01)
  let (x, y, _, _) = g().node_rect(d.node.val)
  assert_true((x - 6.0 * p).abs() < 0.01)
  assert_true((y - 6.0 * p).abs() < 0.01)
  // the page beside it laid out where the dock ends now, its margin moved on the same clock
  let (px, _, _, _) = g().node_rect(d.page.val)
  assert_true((px - (6.0 * p + w + 6.0 * p + 8.0 * p)).abs() < 0.01)
  // its end: what is built, and nothing moves after it
  t.run_for(dock_ms - half)
  assert_true((t.time() - (start + dock_ms)).abs() < 1.0e-6)
  assert_eq(width_of(d.node.val), 56.0)
  t.assert_idle()
}

///|
/// How late a move's first frame is to the screen in these tests (a page built in it), and one far later than a move
/// waits for (nav_late_most).
let move_first_late_ms : Double = 40.0

///|
let move_first_very_late_ms : Double = 500.0

///|
test "a move whose first frames are late one after another (its state built over two: a native view made in the second) waits for each" {
  // the same move, on time: half its time in
  let on_time = Dock::new()
  let t = Tester::new(on_time.view(), w=800.0, h=600.0)
  t.draw()
  on_time.fold.val = true
  t.draw()
  t.run_for(dock_ms / 2.0)
  let half = width_of(on_time.node.val)
  let d = Dock::new()
  let t = Tester::new(d.view(), w=800.0, h=600.0)
  t.draw()
  d.fold.val = true
  t.draw()
  let start = t.time()
  t.frame_late(move_first_late_ms)
  t.run_for(first_frame_ms)
  t.frame_late(move_first_late_ms)
  t.run_for(first_frame_ms)
  // (each late frame's time not run: as on time, from the second's)
  t.run_for(start + 2.0 * move_first_late_ms + dock_ms / 2.0 - t.time())
  assert_true((width_of(d.node.val) - half).abs() < 1.0e-6, msg="\{width_of(d.node.val)} against \{half}")
  t.run_for(start + 2.0 * move_first_late_ms + dock_ms - t.time())
  assert_eq(width_of(d.node.val), 56.0)
  t.assert_idle()
}

///|
test "a move whose first frame is late to the screen moves from where that frame drew it, at the display's pace; nav_late_most at most" {
  // the same move, its first frame on time: half its time in
  let on_time = Dock::new()
  let t = Tester::new(on_time.view(), w=800.0, h=600.0)
  t.draw()
  on_time.fold.val = true
  t.draw()
  t.run_for(dock_ms / 2.0)
  let half = width_of(on_time.node.val)
  // its first frame (the one it set out in, the new state built in it) late to the screen, as the host says in the next
  let d = Dock::new()
  let t = Tester::new(d.view(), w=800.0, h=600.0)
  t.draw()
  d.fold.val = true
  t.draw()
  let start = t.time()
  t.frame_late(move_first_late_ms)
  t.run_for(first_frame_ms)
  // not moved yet: where its first frame drew it
  assert_eq(width_of(d.node.val), 300.0)
  // from then, as the one on time from its frame
  t.run_for(start + move_first_late_ms + dock_ms / 2.0 - t.time())
  assert_true((width_of(d.node.val) - half).abs() < 1.0e-6)
  t.run_for(start + move_first_late_ms + dock_ms - t.time())
  assert_eq(width_of(d.node.val), 56.0)
  t.assert_idle()
  // far later: it waits nav_late_most, no more
  d.fold.val = true
  t.draw()
  let start = t.time()
  t.frame_late(move_first_very_late_ms)
  t.run_for(first_frame_ms)
  t.run_for(start + nav_late_most + (dock_ms / 2.0).floor() - t.time())
  assert_true((width_of(d.node.val) - (56.0 + (300.0 - 56.0) * Ease::Move.at((dock_ms / 2.0).floor() / dock_ms))).abs() < 1.0e-6)
  t.run_for(start + nav_late_most + dock_ms - t.time())
  assert_eq(width_of(d.node.val), 300.0)
  t.assert_idle()
}

///|
test "a move said again over one going on goes on from where that had got to" {
  let d = Dock::new()
  let t = Tester::new(d.view(), w=800.0, h=600.0)
  t.draw()
  d.fold.val = true
  t.draw()
  // (some way in, not half: a point the curve does not come back to)
  t.run_for(dock_ms * 0.4)
  let there = width_of(d.node.val)
  assert_true(there < 300.0 && there > 56.0)
  // opened again: from where it was, not from its folded width
  d.fold.val = true
  t.draw()
  assert_eq(width_of(d.node.val), there)
  t.run_for(dock_ms / 4.0)
  let later = width_of(d.node.val)
  assert_true(later > there && later < 300.0)
  // as long as what was left of its way from when it was said: no longer than its whole
  assert_true(move_ms(300.0 - there) <= dock_ms)
  t.run_for(move_ms(300.0 - there) * 3.0 / 4.0)
  assert_eq(width_of(d.node.val), 300.0)
}

///|
test "what a move does not list is at once what is built" {
  let d = Dock::new()
  let t = Tester::new(d.view(props=["margin"]), w=800.0, h=600.0)
  t.draw()
  d.fold.val = true
  t.draw()
  t.run_for(dock_ms / 2.0)
  // its width not listed: folded at once; its margin moving
  assert_eq(width_of(d.node.val), 56.0)
  let (x, _, _, _) = g().node_rect(d.node.val)
  assert_true(x > 0.0 && x < 6.0)
}

///|
test "a value of the view's own moves with the boxes that list it" {
  let folded = Ref(false)
  let fold = Ref(false)
  let line = Ref(-1.0)
  let t = Tester::new(
    fn(c) {
      if fold.val {
        fold.val = false
        c.move_state([("dock", ["--dock-line"])])
        folded.val = !folded.val
      }
      line.val = c.moved("--dock-line", if folded.val { 1.0 } else { 0.0 })
    },
    w=200.0,
    h=200.0,
  )
  t.draw()
  assert_eq(line.val, 0.0)
  fold.val = true
  t.draw()
  // (a value of 0 to 1: as long as a Move of a point)
  t.run_for(move_ms(1.0) / 2.0)
  assert_true((line.val - Ease::Move.at(0.5)).abs() < 0.000001)
  t.run_for(move_ms(1.0) / 2.0)
  assert_eq(line.val, 1.0)
}

///|
test "margins as CSS's: around the box, below 0 pulling it over what is before it" {
  let mid = Ref(-1)
  let last = Ref(-1)
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Fill(1.0), pad=10.0, fn() {
        c.box(w=Px(50.0), h=Px(20.0), fn() {  }) |> ignore
        mid.val = c.box(w=Px(50.0), h=Px(20.0), ml=-10.0, mt=4.0, fn() {  })
        last.val = c.box(w=Px(50.0), h=Px(20.0), mx=6.0, fn() {  })
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  let (mx, my, _, _) = g().node_rect(mid.val)
  assert_eq(mx, 50.0)
  assert_eq(my, 14.0)
  let (lx, _, _, _) = g().node_rect(last.val)
  assert_eq(lx, 106.0)
}

///|
test "a box put where it is said: from its parent's edges, its padding not kept, out of the flow" {
  let parent = Ref(-1)
  let put = Ref(-1)
  let after = Ref(-1)
  let half = Ref(-1)
  let t = Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), pad=30.0, fn() {
        parent.val = c.box(w=Px(200.0), h=Px(100.0), pad=10.0, fn() {
          // a bar along its right edge, 8 in from the top and the bottom
          put.val = c.box(w=Px(4.0), right=0.0, top=8.0, bottom=8.0, fn() {  })
          // what follows it laid out as if it were not there
          after.val = c.box(w=Px(20.0), h=Px(20.0), fn() {  })
          // half the parent's room inside its padding
          half.val = c.box(w=Pct(50.0), h=Px(10.0), fn() {  })
        })
      })
      |> ignore
    },
    w=400.0,
    h=400.0,
  )
  t.draw()
  let (px, py, pw, ph) = g().node_rect(parent.val)
  let (x, y, w, h) = g().node_rect(put.val)
  assert_eq(w, 4.0)
  assert_eq(x + w, px + pw)
  assert_eq(y, py + 8.0)
  assert_eq(h, ph - 16.0)
  let (ax, ay, _, _) = g().node_rect(after.val)
  assert_eq(ax, px + 10.0)
  assert_eq(ay, py + 10.0)
  assert_eq(width_of(half.val), (200.0 - 20.0) / 2.0)
}
