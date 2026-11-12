// A key of the window's tree drawn smaller than a press's room over a node hosting an old view (an app's shell: its
// pages' small keys over the old view the whole window is): where the old view has nothing of its own under the press
// (none of its targets, nor its room round one, nor words of it to pick), the key is reached from round it as anywhere
// (Tree::reached, asking the host Tree::hosts_at); where it has, the old view's. By real presses (a finger down and up,
// a mouse moved over it), what lights and shapes the pointer what a press there presses.

///|
let ro_key_presses : Array[Int] = [0]

///|
let ro_old_presses : Array[Int] = [0]

///|
let ro_lit : Int64 = 0xCC3333FFL

///|
/// What the old view draws where the key is: nothing (0), a button of its own 37 by 24 ending 3 before the key's left,
/// 110 down (1), words to pick across the key's left, 106 down (2), a list of 40 rows 50 high a finger scrolls, nothing in it
/// pressed (3).
fn ro_old(c : Ctx, what : Int) -> Unit {
  c.mouse_drags_lists(false)
  c.column(w=Fill(1.0), h=Fill(1.0), fn() {
    match what {
      1 =>
        c.box(dir=Row, fn() {
          c.box(w=Px(60.0), h=Px(134.0), fn() {  }) |> ignore
          c.column(fn() {
            c.box(w=Px(37.0), h=Px(110.0), fn() {  }) |> ignore
            let id = c.id("old-key")
            c.on_press(id, fn() { ro_old_presses[0] = ro_old_presses[0] + 1 })
            c.box(id~, w=Px(37.0), h=Px(24.0), fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      2 => {
        c.box(w=Px(300.0), h=Px(106.0), fn() {  }) |> ignore
        c.box(w=Px(300.0), fn() {
          c.selectable(fn() {
            c.rich([plain("words of the old view to pick, across the key")], size=15.0, line=22.0, color=0x333333FFL)
            |> ignore
          })
        })
        |> ignore
      }
      3 =>
        c.list("rows", 40, 50.0, fn(i) {
          c.box(w=Fill(1.0), h=Px(50.0), bg=if i % 2 == 0 { 0xF4F4F4FFL } else { 0xFFFFFFFFL }, fn() {  }) |> ignore
        })
        |> ignore
      _ => c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A Tester by a keyboard and mouse (platform 0, a room 36 across) or a finger (2, 44), 400 by 400, the whole window an
/// old view (`what`: ro_old) and over it a key of the tree's 34 by 34 at (100, 100), lit as pointed, a hand over it; the
/// tree, the key.
fn ro_tester(platform : Int, what : Int) -> (Tester, @view.Tree, @view.NodeId) {
  ro_key_presses[0] = 0
  ro_old_presses[0] = 0
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform~)
  t.check_looks(false)
  let key : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(400.0))) |> ignore
      old(b, fn(c) { ro_old(c, what) }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(n) {
      key.val = Some(n.id())
      n
      .over(Is(true))
      .offset(Is((100.0, 100.0)))
      .width(Is(Some(34.0)))
      .height(Is(Some(34.0)))
      .presses(Is(true))
      .says(Is(Some(@view.said(Button, label="key"))))
      .cursor(Is(Some(@view.Cursor::Hand)))
      .on_press(fn() { ro_key_presses[0] = ro_key_presses[0] + 1 })
      .ground(By(fn() { if n.pointed() { ro_lit } else { 0xEEEEEEFFL } }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, view_app.val.unwrap(), key.val.unwrap())
}

///|
/// Whether the key is drawn lit in the next frame.
fn ro_key_lit(t : Tester) -> Bool {
  t.frame_at(t.time() + frame_period_default)
  t.drawn_rects().iter().any(fn(r) { r.4 == ro_lit })
}

///|
test "a key of the tree over an old view with nothing there: a finger down and up past its edge, in its room, presses it; past its room, not" {
  // (34 across, a finger's room 44: 5 round it each way)
  let (t, _, _) = ro_tester(2, 0)
  t.tap(96.0, 117.0)
  assert_eq(ro_key_presses[0], 1, msg="4 left of it")
  t.tap(117.0, 138.5)
  assert_eq(ro_key_presses[0], 2, msg="4.5 below it")
  t.tap(94.0, 117.0)
  assert_eq(ro_key_presses[0], 2, msg="6 left of it, past its room")
  t.tap(117.0, 140.0)
  assert_eq(ro_key_presses[0], 2, msg="6 below it, past its room")
}

///|
test "a key of the tree over an old view with nothing there, by a mouse: clicked, lit and the hand shown past its edge in its room alike; past its room, none" {
  // (34 across, a keyboard and mouse's room 36: 1 round it each way)
  let (t, tree, key) = ro_tester(0, 0)
  t.move_to(99.5, 117.0)
  assert_true(tree.pointed_now() == Some(key), msg="pointed 0.5 left of it")
  assert_true(ro_key_lit(t), msg="lit 0.5 left of it")
  assert_true(t.cursor() is Hand, msg="the hand 0.5 left of it")
  t.tap(99.5, 117.0)
  assert_eq(ro_key_presses[0], 1, msg="clicked 0.5 left of it")
  t.move_to(98.5, 117.0)
  assert_true(tree.pointed_now() is None, msg="pointed 1.5 left of it")
  assert_true(!ro_key_lit(t), msg="lit 1.5 left of it")
  assert_true(!(t.cursor() is Hand), msg="the hand 1.5 left of it")
  t.tap(98.5, 117.0)
  assert_eq(ro_key_presses[0], 1, msg="clicked 1.5 left of it")
}

///|
test "a key of the tree over an old view's own key beside it: on the old key and in its room, the old view's; past them, in the tree's key's room, the tree's" {
  // (the old key 60–97 across, 110–134 down: its room by a finger 3.5 round it across, to 100.5, and 10 down,
  // 100–144)
  let (t, _, _) = ro_tester(2, 1)
  t.tap(96.0, 122.0)
  assert_eq((ro_key_presses[0], ro_old_presses[0]), (0, 1), msg="on the old key")
  t.tap(98.5, 122.0)
  assert_eq((ro_key_presses[0], ro_old_presses[0]), (0, 2), msg="in the old key's room")
  // (above the old key's room, in the tree's key's: the tree's)
  t.tap(96.0, 97.0)
  assert_eq((ro_key_presses[0], ro_old_presses[0]), (1, 2), msg="past the old key's room")
}

///|
test "a key of the tree over words of an old view to pick: past its edge on them, the old view's, the key not pressed nor lit" {
  let (t, tree, _) = ro_tester(2, 2)
  let island = match tree.target_at(50.0, 117.0) {
    Hosted(h) => h
    _ => @halt.saying("the old view not found on its words")
  }
  // (on its words, 4 left of the key: the old view has them there)
  guard old_taker_at(tree, island, 96.0, 117.0) is Some(k) && k % 2 == 1 else {
    @halt.saying("no words of the old view's to pick 4 left of the key")
  }
  t.tap(96.0, 117.0)
  assert_eq(ro_key_presses[0], 0)
  assert_true(tree.target_at(96.0, 117.0) == Hosted(island), msg="on the words by the key")
  // (in the key's room above the words, nothing of the old view's there: the key's)
  assert_true(old_taker_at(tree, island, 117.0, 97.5) is None, msg="the old view has something above its words")
  t.tap(117.0, 97.5)
  assert_eq(ro_key_presses[0], 1)
  let (m, mtree, mkey) = ro_tester(0, 2)
  m.move_to(99.5, 117.0)
  assert_true(mtree.pointed_now() != Some(mkey), msg="a mouse on the words by the key")
  assert_true(!ro_key_lit(m), msg="lit on the words by the key")
}

///|
test "a key of the tree over an old view with nothing there: every point of its room and no other is the key's, by each hand" {
  for platform in [0, 2] {
    let (_, tree, key) = ro_tester(platform, 0)
    let island = match tree.target_at(10.0, 10.0) {
      Hosted(h) => h
      _ => @halt.saying("the old view not found")
    }
    let least = if platform == 2 { 44.0 } else { 36.0 }
    // (its room: 34 grown to `least` round its middle, 117)
    let (r0, r1) = (117.0 - least / 2.0, 117.0 + least / 2.0)
    // (a grid of quarter points across it and 3 past it each way, off the grid's edges by an eighth)
    let mut y = r0 - 3.0 + 0.125
    while y < r1 + 3.0 {
      let mut x = r0 - 3.0 + 0.125
      while x < r1 + 3.0 {
        let want : @view.Target = if x >= r0 && x < r1 && y >= r0 && y < r1 { Pressed(key) } else { Hosted(island) }
        assert_true(tree.target_at(x, y) == want, msg="platform \{platform} at (\{x}, \{y})")
        x = x + 0.25
      }
      y = y + 0.25
    }
  }
}

///|
/// A finger's drag from (x, y) up 100 over the key on an old view's list (ro_old's 3), let go there: how far the list
/// scrolled, how many times the key was pressed, and whether (x, y) is the key's as the hit test says.
fn ro_drag_from(x : Double, y : Double) -> (Double, Int, Bool) {
  let (t, tree, key) = ro_tester(2, 3)
  let on = tree.target_at(x, y) == Pressed(key)
  t.drag(x, y, x, y - 100.0, steps=10)
  (t.list_state().offset(), ro_key_presses[0], on)
}

///|
test "a key of the tree over an old view's list: a finger's drag begun in its room past its edge does what one begun in it does" {
  // (the key's room is the key (the coordinator of the migration, 2026-11-11): what a press, a drag or a hold does
  // begun in the ring round it is what it does begun where it is drawn)
  let inside = ro_drag_from(117.0, 117.0)
  let ring = ro_drag_from(96.0, 117.0)
  assert_true(inside.2 && ring.2, msg="the key's where each began: inside \{inside.2}, in its room \{ring.2}")
  assert_eq((ring.0, ring.1), (inside.0, inside.1), msg="(scrolled, pressed) begun in its room against begun in it")
  // (what that is: the key's hold, moved off it, presses nothing, and the old view's list under it is not dragged)
  assert_eq((inside.0, inside.1), (0.0, 0))
}

///|
/// A Tester by a finger (a room 44 across), 400 by 400, the whole window an old view: a frame that takes presses (as a
/// page's list's measured by its id, pressing nothing), in it words to pick 20 to 42 down and again 60 to 82 down; over
/// it a bar 48 high across the window, its ground `ground` (0: none), and on the bar a key of the tree's 34 by 34 at
/// (100, 7); the tree, the key.
fn ro_bar_tester(ground : Int64) -> (Tester, @view.Tree, @view.NodeId) {
  ro_key_presses[0] = 0
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=2)
  t.check_looks(false)
  let key : Ref[@view.NodeId?] = Ref(None)
  let words = fn(c : Ctx, s : String) {
    c.box(w=Px(300.0), fn() {
      c.selectable(fn() { c.rich([plain(s)], size=15.0, line=22.0, color=0x333333FFL) |> ignore })
    })
    |> ignore
  }
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(400.0))) |> ignore
      old(b, fn(c) {
        c.column(w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(id=c.id("whole"), w=Fill(1.0), h=Fill(1.0), fn() {
            c.box(w=Px(300.0), h=Px(20.0), fn() {  }) |> ignore
            words(c, "words under the bar")
            c.box(w=Px(300.0), h=Px(18.0), fn() {  }) |> ignore
            words(c, "words past the bar")
          })
          |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(bar) {
      bar.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(48.0))).ground(Is(ground)) |> ignore
      bar.box(fn(n) {
        key.val = Some(n.id())
        n
        .over(Is(true))
        .offset(Is((100.0, 7.0)))
        .width(Is(Some(34.0)))
        .height(Is(Some(34.0)))
        .presses(Is(true))
        .says(Is(Some(@view.said(Button, label="key"))))
        .on_press(fn() { ro_key_presses[0] = ro_key_presses[0] + 1 })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, view_app.val.unwrap(), key.val.unwrap())
}

///|
test "a key on a bar whose ground hides an old view under it: past its edge in its room, over the old view's words and its frame there, the key's; under no ground, the old view's; past the bar, its words picked by a long press" {
  // (the key 100–134 across, 7–41 down; a finger's room 5 round it)
  let (t, tree, key) = ro_bar_tester(0xFFFFFFFFL)
  let island = match tree.target_at(10.0, 200.0) {
    Hosted(h) => h
    _ => @halt.saying("the old view not found")
  }
  // (what the old view has there, were it seen: its words 4 left of the key, its frame 4 below it)
  assert_true(old_taker_at(tree, island, 96.0, 30.0) is Some(_), msg="the old view's 4 left of it")
  assert_true(old_taker_at(tree, island, 117.0, 45.0) is Some(_), msg="the old view's 4 below it")
  t.tap(96.0, 30.0)
  assert_eq(ro_key_presses[0], 1, msg="4 left of it, over the words under the bar")
  t.tap(117.0, 45.0)
  assert_eq(ro_key_presses[0], 2, msg="4 below it, over the old view's frame under the bar")
  // (a finger down there: the key holds it)
  t.press_at(117.0, 45.0)
  assert_true(tree.holder() == Some(key), msg="held 4 below it")
  t.touch(3, 117.0, 45.0)
  t.draw()
  // (past the bar, on the words there: a long press picks them, the old view's)
  t.press_at(20.0, 71.0)
  t.run_for(long_press_ms)
  assert_eq(t.ctx().selected_text(), "words", msg="held long on the words past the bar")
  t.release(20.0, 71.0)
  assert_eq(ro_key_presses[0], 2)
  // (the bar without a ground of its own, the old view seen through it: what it has there its)
  let (u, _, _) = ro_bar_tester(0L)
  u.tap(96.0, 30.0)
  u.tap(117.0, 45.0)
  assert_eq(ro_key_presses[0], 0, msg="no ground: the old view's under it")
}
