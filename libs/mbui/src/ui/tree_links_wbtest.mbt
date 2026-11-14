// A node's links (runs_links): pressed where their pieces of line are drawn alone, a link broken across lines one
// link; tapped, where it leads told; held or right clicked, told with its piece, no tap after; its pressed ground under
// that link alone.

///|
/// A node 160 wide of words in pieces with a link broken across lines, its links pressed (runs_links), on `platform`
/// (its native input's): the tester, what was tapped and held, and where the link's pieces are in the window; what the
/// links are as shown kept in `links`.
fn links_tester(
  platform? : Int = 0,
  links? : Ref[RunsLinks?] = Ref(None),
) -> (Tester, Array[String], Array[String], Array[(Double, Double, Double, Double)]) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform~)
  t.check_looks(false)
  let runs = [plain("看看 "), link("space.blog 的文档在这里", "https://space.blog/docs"), plain(" 然后再说别的。")]
  let taps : Array[String] = []
  let holds : Array[String] = []
  let id : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(160.0))).lines_up(Is(Some(Start))) |> ignore
      b.box(fn(n) {
        id.val = Some(n.id())
        n
        .words_runs(Is(runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
        |> ignore
        links.val = Some(runs_links(n, fn() { runs }, fn(h) { taps.push(h) }, hold=fn(h, _) { holds.push(h) }))
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = view_app.val.unwrap()
  let d = tree.drawn_of(id.val.unwrap()).unwrap()
  let (r, lay, _) = view_runs_laid(d.runs, d.words_look, d.runs_look, d.w, tree.words_scale_of(d.id))
  let pieces = rich_link_pieces(r, lay, d.x, d.y).map(fn(p) { (p.1, p.2, p.3, p.4) })
  (t, taps, holds, pieces)
}

///|
test "a node's link broken across lines: each piece tapped tells where it leads; the line past its words, and words that lead nowhere, nothing" {
  let (t, taps, _, pieces) = links_tester()
  assert_true(pieces.length() >= 2, msg="across lines: \{Repr(pieces)}")
  for p in pieces {
    t.tap((p.0 + p.2) / 2.0, (p.1 + p.3) / 2.0)
  }
  assert_eq(taps, pieces.map(fn(_) { "https://space.blog/docs" }))
  // (on its first line, past where the link's words end: the line's room, no link)
  let first = pieces[0]
  t.tap(first.2 + 4.0, (first.1 + first.3) / 2.0)
  // (the words before it)
  t.tap(2.0, (first.1 + first.3) / 2.0)
  assert_eq(taps.length(), pieces.length())
}

///|
test "a node's link held a long press's time by a finger, or right clicked: told with where it leads, nothing tapped as it is let go" {
  // (a touch screen's: a finger's hold)
  let (t, taps, holds, pieces) = links_tester(platform=2)
  let p = pieces[0]
  let (x, y) = ((p.0 + p.2) / 2.0, (p.1 + p.3) / 2.0)
  t.press_at(x, y)
  t.run_for(long_press_ms + 50.0)
  t.release(x, y)
  assert_eq(holds, ["https://space.blog/docs"])
  assert_eq(taps, [])
  t.right_click(x, y)
  assert_eq(holds, ["https://space.blog/docs", "https://space.blog/docs"])
  assert_eq(taps, [])
}

///|
test "a node's link pressed: its pressed ground under each of its pieces alone, gone as it is let go" {
  let (t, _, _, pieces) = links_tester()
  let pressed_ground = fn() {
    t
    .drawn_instances()
    .filter(fn(a) { a[5] == 0.0 && a[11] > 0.1 && a[11] < 0.2 && a[8] < 0.1 && a[10] > 0.9 })
    .map(fn(a) { (a[0], a[1], a[2], a[3]) })
  }
  assert_eq(pressed_ground().length(), 0)
  let p = pieces[0]
  t.press_at((p.0 + p.2) / 2.0, (p.1 + p.3) / 2.0)
  let grounds = pressed_ground()
  assert_eq(grounds.length(), pieces.length(), msg="\{Repr(grounds)} for \{Repr(pieces)}")
  for g in grounds {
    assert_true(
      pieces.iter().any(fn(q) { g.0 >= q.0 - 2.5 && g.0 + g.2 <= q.2 + 2.5 && g.1 >= q.1 - 0.5 && g.1 + g.3 <= q.3 + 0.5 }),
      msg="under a piece of it: \{Repr(g)} in \{Repr(pieces)}",
    )
  }
  t.release((p.0 + p.2) / 2.0, (p.1 + p.3) / 2.0)
  assert_eq(pressed_ground().length(), 0)
}

///|
test "a node's link pointed at by the mouse: which one, by its first run, as the pointer moves onto it; none off it" {
  let links : Ref[RunsLinks?] = Ref(None)
  let (t, _, _, pieces) = links_tester(links~)
  let pointed = fn() { links.val.unwrap().pointed.get() }
  let p = pieces[1]
  t.move_to((p.0 + p.2) / 2.0, (p.1 + p.3) / 2.0)
  assert_eq(pointed(), 1)
  // (past its words on its line, then off the node)
  t.move_to(pieces[0].2 + 4.0, (pieces[0].1 + pieces[0].3) / 2.0)
  assert_eq(pointed(), -1)
  t.move_to((p.0 + p.2) / 2.0, (p.1 + p.3) / 2.0)
  t.move_to(390.0, 390.0)
  assert_eq(pointed(), -1)
}

///|
/// What a node of words in pieces with links (runs_links) has come to, made by links_made.
priv struct LinksMade {
  t : Tester
  taps : Array[String]
  holds : Array[(String, (Double, Double, Double, Double))]
  links : Ref[RunsLinks?]
}

///|
/// A node 160 wide of `runs` (as they are now), its links pressed (runs_links, a hold of its own where `holds`), in a
/// box drawn `scale` as big, moved by (40, 30); a box over it while `covered`, taking presses; on `platform`.
fn links_made(
  runs : @signals.Signal[Array[Run]],
  holds? : Bool = true,
  scale? : Double = 1.0,
  covered? : @signals.Signal[Bool] = @signals.signal(false),
  platform? : Int = 0,
) -> LinksMade {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform~)
  t.check_looks(false)
  let taps : Array[String] = []
  let held : Array[(String, (Double, Double, Double, Double))] = []
  let links : Ref[RunsLinks?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(160.0))).lines_up(Is(Some(Start))).offset(Is((40.0, 30.0))).scale(Is(scale)) |> ignore
      b.box(fn(n) {
        n
        .words_runs(By(fn() { runs.get() }), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
        |> ignore
        let hold = if holds { Some(fn(h : String, r : (Double, Double, Double, Double)) { held.push((h, r)) }) } else { None }
        links.val = Some(runs_links(n, fn() { runs.get() }, fn(h) { taps.push(h) }, hold?))
      })
      |> ignore
    })
    |> ignore
    root.show(fn() { covered.get() }, fn(o) {
      o.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(400.0))).presses(Is(true)).on_press(fn() {  }) |> ignore
    })
  })
  t.draw()
  { t, taps, holds: held, links }
}

///|
/// The glyphs drawn in a link's ink (the link colour as its paragraph has it: runs_plain's), where each is in the window.
fn link_glyphs(t : Tester) -> Array[(Double, Double, Double, Double)] {
  t
  .drawn_instances()
  .filter(fn(a) { a[5] == 1.0 && a[8] < 0.1 && a[9] > 0.5 && a[9] < 0.55 && a[10] > 0.9 })
  .map(fn(a) { (a[0], a[1], a[2], a[3]) })
}

///|
let linked_runs : Array[Run] = [plain("看看 "), link("space.blog 的文档在这里", "https://space.blog/docs"), plain(" 然后再说别的。")]

///|
test "a node's link in a box drawn half as big and moved: a glyph of it tapped where it is drawn tells where it leads, on each of its lines; held, told the piece where it is drawn in the window" {
  let m = links_made(@signals.signal(linked_runs), scale=0.5, platform=2)
  let glyphs = link_glyphs(m.t)
  assert_true(glyphs.length() > 4, msg="its glyphs drawn: \{glyphs.length()}")
  let first = glyphs[0]
  let last = glyphs[glyphs.length() - 1]
  assert_true(last.1 > first.1, msg="across lines: \{Repr(first)} \{Repr(last)}")
  for g in [first, last] {
    m.t.tap(g.0 + g.2 / 2.0, g.1 + g.3 / 2.0)
  }
  assert_eq(m.taps, ["https://space.blog/docs", "https://space.blog/docs"])
  let (x, y) = (first.0 + first.2 / 2.0, first.1 + first.3 / 2.0)
  m.t.press_at(x, y)
  m.t.run_for(long_press_ms + 50.0)
  m.t.release(x, y)
  assert_eq(m.holds.length(), 1)
  let (_, (rx, ry, rw, rh)) = m.holds[0]
  assert_true(x >= rx && x < rx + rw && y >= ry && y < ry + rh, msg="the piece held, in the window: \{Repr(m.holds[0])} round \{Repr((x, y))}")
  // (its words' height as drawn, half its line's)
  assert_true(rh <= 11.5, msg="as big as drawn: \{rh}")
}

///|
test "a node's link with no hold of its own held a long press's time by a finger and let go on it: tapped, as an old view's; with one, a mouse's long press let go on it tapped too" {
  let m = links_made(@signals.signal(linked_runs), holds=false, platform=2)
  let g = link_glyphs(m.t)[0]
  let (x, y) = (g.0 + g.2 / 2.0, g.1 + g.3 / 2.0)
  m.t.press_at(x, y)
  m.t.run_for(long_press_ms + 50.0)
  m.t.release(x, y)
  assert_eq(m.taps, ["https://space.blog/docs"])
  let m = links_made(@signals.signal(linked_runs), platform=0)
  let g = link_glyphs(m.t)[0]
  let (x, y) = (g.0 + g.2 / 2.0, g.1 + g.3 / 2.0)
  m.t.press_at(x, y)
  m.t.run_for(long_press_ms + 50.0)
  m.t.release(x, y)
  assert_eq(m.taps, ["https://space.blog/docs"])
  assert_eq(m.holds.length(), 0)
}

///|
test "a node's link pointed at by a pointer that stays where it is: covered, none; uncovered, it again; its words changed under it, the one now there" {
  let covered = @signals.signal(false)
  let runs = @signals.signal(linked_runs)
  let m = links_made(runs, covered~)
  let pointed = fn() { m.links.val.unwrap().pointed.get() }
  let g = link_glyphs(m.t)[0]
  m.t.move_to(g.0 + g.2 / 2.0, g.1 + g.3 / 2.0)
  assert_eq(pointed(), 1)
  covered.set(true)
  m.t.draw()
  assert_eq(pointed(), -1, msg="covered")
  covered.set(false)
  m.t.draw()
  assert_eq(pointed(), 1, msg="uncovered")
  // (another link before it, as long as the words it pushes along: the one under the pointer now)
  runs.set([plain("看看 "), link("另一个", "https://space.blog/other"), plain(" "), link("space.blog 的文档在这里", "https://space.blog/docs")])
  m.t.draw()
  assert_eq(pointed(), 1, msg="the other, its first run 1 too: under the pointer now")
  runs.set([link("看看 也是一个链接", "https://space.blog/a"), plain(" "), link("space.blog 的文档在这里", "https://space.blog/docs")])
  m.t.draw()
  assert_eq(pointed(), 0, msg="the first now under it")
}

///|
/// Two links on one line in a node 300 by 40 of words `size` large, moved by `dx` (what holds it): the tester, what was
/// tapped, the links as shown.
fn two_links(dx : @signals.Signal[Double], size : @signals.Signal[Double]) -> (Tester, Array[String], RunsLinks) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  let runs = [link("甲甲甲甲", "https://a"), plain(" "), link("乙乙乙乙", "https://b")]
  let taps : Array[String] = []
  let links : Ref[RunsLinks?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.lines_up(Is(Some(Start))).offset(By(fn() { (dx.get(), 0.0) })) |> ignore
      b.box(fn(n) {
        n
        .width(Is(Some(300.0)))
        .height(Is(Some(40.0)))
        .words_runs(Is(runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
        .words_look(By(fn() { { size: size.get(), weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 } }))
        |> ignore
        links.val = Some(runs_links(n, fn() { runs }, fn(h) { taps.push(h) }))
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, taps, links.val.unwrap())
}

///|
test "a node's link under a pointer that stays where it is, what holds the node moved under it (the node as big): the other link of the same node pointed at now" {
  let dx = @signals.signal(0.0)
  let (t, _, links) = two_links(dx, @signals.signal(15.0))
  // (over the second, 4 glyphs of 15 and a space past the first: about 70 in)
  t.move_to(80.0, 10.0)
  assert_eq(links.pointed.get(), 2)
  // (the node moved right by 70: the first under the pointer now)
  view_app.val.unwrap().event(t.time(), fn() { dx.set(60.0) })
  assert_eq(links.pointed.get(), 0, msg="at the change, no frame")
}

///|
test "a node's link under a pointer that stays where it is, its words set larger (the node as big): the link now under it pointed at; tapped at once after, no frame between, that one" {
  let size = @signals.signal(15.0)
  let (t, taps, links) = two_links(@signals.signal(0.0), size)
  t.move_to(80.0, 10.0)
  assert_eq(links.pointed.get(), 2)
  // (words twice as large, told as an event from outside is (as what the app is told comes): the first reaches past
  // 80)
  view_app.val.unwrap().event(t.time(), fn() { size.set(30.0) })
  assert_eq(links.pointed.get(), 0, msg="at the change, no frame")
  t.tap(80.0, 10.0)
  assert_eq(taps, ["https://a"])
}

///|
test "a node's link under a pointer that stays where it is, the system's size of words made larger (the node as big): the link now under it pointed at, as its words are measured again" {
  let (t, _, links) = two_links(@signals.signal(0.0), @signals.signal(15.0))
  t.move_to(80.0, 10.0)
  assert_eq(links.pointed.get(), 2)
  // (twice as large: as the frame it is told in begins, the window's words measured again: Tree::words_again)
  t.set_font_scale(2.0)
  t.draw()
  assert_eq(links.pointed.get(), 0)
}
