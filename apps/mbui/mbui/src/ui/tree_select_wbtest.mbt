// Words of the window's tree picked with the pointer (tree_select.mbt): a node's words in pieces where what holds it
// says so (words_picked), dragged over with a mouse, picked as an old view's paragraph of the same pieces is; what of
// them is picked drawn under them; none where it does not say so, nor with a finger.

///|
let picked_runs : Array[Run] = [plain("hello "), bold("wide"), plain(" world")]

///|
test "a word picked by a still finger stays that word when its paragraph moves; sliding the finger then extends it" {
  for retained in [false, true] {
    let shifted = @signals.signal(0.0)
    let t = Tester::new(fn(_) { }, w=400.0, h=300.0, platform=2)
    set_view_app(fn(root) {
      if retained {
        root.box(fn(p) {
          words_picked(p)
          p.offset(By(fn() { (0.0, 40.0 + shifted.get()) }))
          .width(Is(Some(300.0)))
          .words_runs(Is(picked_runs), look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own }) |> ignore
        }) |> ignore
      } else {
        old(root, fn(c) {
          c.box(top=40.0 + shifted.get(), w=Px(300.0), fn() {
            c.selectable(fn() { c.rich(picked_runs, size=15.0, line=22.0) |> ignore })
          }) |> ignore
        }).grow(Is(1.0)) |> ignore
      }
    })
    t.draw()
    t.press_at(60.0, 51.0)
    t.run_for(long_press_ms)
    assert_eq(t.ctx().selected_text(), "wide")
    shifted.set(80.0)
    t.draw()
    t.move(60.0, 51.0)
    t.draw()
    assert_eq(t.ctx().selected_text(), "wide", msg="the paragraph moved, retained=\{retained}")
    t.move(200.0, 131.0)
    t.draw()
    assert_eq(t.ctx().selected_text(), "wide world", msg="the finger moved, retained=\{retained}")
    t.release(200.0, 131.0)
  }
}

///|
/// A node of picked_runs 300 wide 40 down (its line in its middle where `centered`), in a page whose words are picked
/// where `picks` (words_picked), on `platform`.
fn tree_picked_tester(picks : Bool, platform? : Int = 0, centered? : Bool = false) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform~)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.padding(Is((0.0, 40.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      if picks {
        words_picked(page)
      }
      page.box(fn(n) {
        n
        .width(Is(Some(300.0)))
        .words_runs(Is(picked_runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false })
        .words_centered(Is(centered))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  t
}

///|
/// The same words as an old view's paragraph whose words are picked (Ctx::selectable), 40 down.
fn old_picked_tester() -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.mouse_drags_lists(false)
      c.column(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(w=Px(300.0), h=Px(40.0), fn() {  }) |> ignore
        c.box(w=Px(300.0), fn() {
          c.selectable(fn() { c.rich(picked_runs, size=15.0, line=22.0, color=0x333333FFL) |> ignore })
        })
        |> ignore
      })
      |> ignore
    })
    .grow(Is(1.0))
    |> ignore
  })
  t.draw()
  t.drawn_now()
  t
}

///|
/// The rects drawn in the colour what is picked is drawn under (desk's sel_color).
fn picked_drawn(t : Tester) -> Array[(Double, Double, Double, Double)] {
  t
  .drawn_instances()
  .filter(fn(a) { a[5] == 0.0 && a[8] > 0.2 && a[8] < 0.25 && a[9] > 0.5 && a[9] < 0.53 && a[10] > 0.95 })
  .map(fn(a) { (a[0], a[1], a[2], a[3]) })
}

///|
test "a node's words in pieces in a page whose words are picked: dragged over with the mouse, picked as an old view's paragraph of the same pieces is (from where it went down to where it let go), drawn picked under them; a press elsewhere lets them go" {
  for case in [(1.0, 300.0, "hello wide world"), (1.0, 60.0, "hello w")] {
    let (x0, x1, _) = case
    let old = old_picked_tester()
    let next = dragged_at(old, x0, 51.0, x1, 51.0, old.time(), true)
    old.frame_at(next)
    let old_said = old.ctx().selected_text()
    let old_drawn_now = picked_drawn(old)
    let t = tree_picked_tester(true)
    let next = dragged_at(t, x0, 51.0, x1, 51.0, t.time(), true)
    t.frame_at(next)
    assert_eq(t.ctx().selected_text(), old_said, msg="\{case}")
    assert_true(old_said != "", msg="the old one picked: \{case}")
    // (drawn picked where the old one is, as big)
    let old_drawn = old_drawn_now
    assert_true(old_drawn.length() > 0, msg="the old one drawn picked: \{case}")
    assert_eq(picked_drawn(t), old_drawn, msg="drawn picked: \{case}")
    // (pressed under them, where no words are: let go)
    let next = dragged_at(t, 350.0, 250.0, 350.0, 250.0, next + double_click_ms, true)
    t.frame_at(next)
    assert_eq(t.ctx().selected_text(), "")
    assert_eq(picked_drawn(t).length(), 0)
  }
}

///|
test "a node's words in pieces picked by none where nothing says its words are, nor by a finger where something does" {
  for case in [(false, 0), (true, 2)] {
    let (picks, platform) = case
    let t = tree_picked_tester(picks, platform~)
    let next = dragged_at(t, 1.0, 51.0, 300.0, 51.0, t.time(), true)
    t.frame_at(next)
    assert_eq(t.ctx().selected_text(), "", msg="\{case}")
  }
}

///|
test "a node's words in pieces with its line in its middle: dragged from its first glyph to where its fifth begins, those four picked, drawn picked from where its first glyph is" {
  let t = tree_picked_tester(true, centered=true)
  let glyphs = t.drawn_instances().filter(fn(a) { a[5] == 1.0 }).map(fn(a) { (a[0], a[1], a[2], a[3]) })
  glyphs.sort_by(fn(a, b) { a.0.compare(b.0) })
  assert_true(glyphs[0].0 > 20.0, msg="in its middle: \{glyphs[0]}")
  // (where its words are said to be (Tester::run_rects) where they are drawn: in its middle too)
  let rs = t.run_rects("hello")
  assert_true(rs.length() == 1 && (rs[0].0 - glyphs[0].0).abs() < 2.0, msg="run_rects: \{rs} \{glyphs[0]}")
  // (its last move, the fifth of six (dragged_at: the sixth lets go where it is), where the fifth glyph begins)
  let (x0, to) = (glyphs[0].0 + 0.5, glyphs[4].0 + 0.5)
  let next = dragged_at(t, x0, 51.0, x0 + (to - x0) * 6.0 / 5.0, 51.0, t.time(), true)
  t.frame_at(next)
  let drawn = picked_drawn(t)
  assert_eq(t.ctx().selected_text(), "hell")
  assert_eq(drawn.length(), 1)
  assert_true((drawn[0].0 - glyphs[0].0).abs() < 2.0, msg="from its first glyph: \{drawn} \{glyphs[0]}")
}

///|
test "words picked in a page's list scrolled away and back (the nodes that show them made anew), then a block put before them: picked as they were, drawn picked again under the same words, once each; nothing found again as frames go by" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  let s = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(40, fn(i) { i }))
  // (something moving beside them all along, nothing of it theirs)
  let spin = @signals.signal(0.0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(200.0))).width(Is(Some(300.0))) |> ignore
      words_picked(page)
      page.scrolls_window(s, fn() { keys.get() }, est=22.0, fn(b, i) {
        b.box(fn(n) {
          n
          .words_runs(Is([plain("第 \{i} 段 "), bold("hello")]), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(m) {
      m.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0))).offset(By(fn() { (350.0, spin.get()) })).ground(Is(0xFF0000FFL))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  // (from the first's start to the second's end)
  let next = dragged_at(t, 1.0, 11.0, 1.0 + 299.0 * 6.0 / 5.0, 11.0 + 26.0 * 6.0 / 5.0, t.time(), true)
  t.frame_at(next)
  let said = t.ctx().selected_text()
  assert_true(said.contains("第 0 段") && said.contains("第 1 段 hello"), msg="\{said}")
  let drawn = picked_drawn(t)
  assert_true(drawn.length() >= 2, msg="drawn picked: \{drawn}")
  // (frames with something else moving: nothing found again)
  let found = tree_sels_made.val
  for k in 0..<5 {
    spin.set(k.to_double() * 10.0)
    t.frame_at(t.time() + 16.0)
  }
  assert_eq(tree_sels_made.val, found, msg="found again as frames went by")
  // (away past where they show, then back)
  t.wheel(150.0, 100.0, 600.0)
  t.run_for(move_most_ms)
  assert_eq(picked_drawn(t).length(), 0, msg="none shows")
  t.wheel(150.0, 100.0, -600.0)
  t.run_for(move_most_ms)
  assert_eq(t.ctx().selected_text(), said)
  assert_eq(picked_drawn(t), drawn)
  // (a block put before them: the same words picked, drawn picked under the same words (the list held where it
  // showed: what is over what shows grown, the column moved with it))
  keys.set([-1] + Array::makei(40, fn(i) { i }))
  t.run_for(move_most_ms)
  assert_eq(t.ctx().selected_text(), said)
  assert_eq(picked_drawn(t), drawn)
  assert_true(t.find("第 -1 段 hello") is None, msg="the one put before them over where it shows")
}

///|
/// A page 300 wide, `height` high, of 40 blocks of words in pieces picked with the mouse, laid out nowhere while
/// `hidden`: the tester and where its list is scrolled to.
fn picked_list_tester(height : @signals.Signal[Double], hidden : @signals.Signal[Bool]) -> (Tester, @view.Scroll) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  t.check_looks(false)
  let s = @view.Scroll::list()
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(By(fn() { Some(height.get()) })).width(Is(Some(300.0))).laid_nowhere(By(fn() { hidden.get() })) |> ignore
      words_picked(page)
      page.scrolls_window(s, fn() { Array::makei(40, fn(i) { i }) }, est=22.0, fn(b, i) {
        b.box(fn(n) {
          n
          .words_runs(Is([plain("第 \{i} 段 "), bold("hello")]), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, s)
}

///|
test "words picked held past a page's list's foot, the list shorter under a pointer that stays where it is: brought on then; the page laid out nowhere while held: still, and known no more" {
  let height = @signals.signal(300.0)
  let hidden = @signals.signal(false)
  let (t, _) = picked_list_tester(height, hidden)
  // (pressed on the first, held at 250: within the list)
  finger(0, 2.0, 11.0)
  t.frame_at(t.time() + 16.0)
  finger(1, 60.0, 250.0)
  t.frame_at(t.time() + 16.0)
  assert_true(tree_edge.val is Some({ speed: 0.0, .. }), msg="within it: still")
  // (the list made 200 high under the pointer held at 250: past its foot now, brought on)
  height.set(200.0)
  t.frame_at(t.time() + 16.0)
  assert_true(tree_edge.val is Some({ speed, .. }) && speed > 0.0, msg="past its foot: brought on")
  // (frame after frame, the pointer still: what is picked growing as the column comes on, each two frames more)
  let mut was = t.ctx().selected_text()
  for k in 0..<10 {
    t.frame_at(t.time() + 16.0)
    t.frame_at(t.time() + 16.0)
    let now = t.ctx().selected_text()
    assert_true(now.length() > was.length() && now.has_prefix(was), msg="frame \{k}: \{was} -> \{now}")
    was = now
  }
  t.frame_at(t.time() + 300.0)
  let picked = t.ctx().selected_text()
  assert_true(picked.contains("第 15 段"), msg="picking on as it came: \{picked}")
  // (laid out nowhere while held: still, the column known no more)
  hidden.set(true)
  t.frame_at(t.time() + 16.0)
  let state = match tree_edge.val {
    Some(e) =>
      match e.scroll.shown_by() {
        Some(v) => "shown by a node, nowhere \{v.shown_nowhere()}, rect \{v.rect()}, speed \{e.speed}"
        None => "shown by none"
      }
    None => "none"
  }
  assert_true(tree_edge.val is None, msg="known no more: \{state}")
  finger(2, 60.0, 250.0)
  t.frame_at(t.time() + 16.0)
}

///|
test "words picked in a page's list, let go, then the page laid out nowhere: what was picked kept whole, nothing picking on" {
  let height = @signals.signal(300.0)
  let hidden = @signals.signal(false)
  let (t, _) = picked_list_tester(height, hidden)
  finger(0, 2.0, 11.0)
  t.frame_at(t.time() + input_step_ms)
  finger(1, 60.0, 120.0)
  t.frame_at(t.time() + input_step_ms)
  finger(1, 60.0, 250.0)
  t.frame_at(t.time() + input_step_ms)
  finger(2, 60.0, 250.0)
  t.frame_at(t.time() + input_step_ms)
  let kept = t.ctx().selected_text()
  assert_true(kept.contains("第 0 段") && kept.contains("第 9 段"), msg="\{kept}")
  assert_false(picked.dragging, msg="let go: picking no more")
  hidden.set(true)
  t.frame_at(t.time() + input_step_ms)
  t.frame_at(t.time() + move_most_ms)
  assert_eq(t.ctx().selected_text(), kept, msg="laid out nowhere")
}

///|
test "a node's words in pieces in a page whose words are picked: a finger held still on them a long press's time picks the word under it, the menu over it once lifted; a tap elsewhere lets it go" {
  let t = tree_picked_tester(true, platform=2)
  t.press_at(60.0, 51.0)
  assert_eq(t.ctx().selected_text(), "")
  t.run_for(long_press_ms)
  assert_eq(t.ctx().selected_text(), "wide")
  t.release(60.0, 51.0)
  t.draw()
  assert_true(t.text_menu().0)
  t.tap(200.0, 250.0)
  t.draw()
  assert_eq(t.ctx().selected_text(), "")
}
