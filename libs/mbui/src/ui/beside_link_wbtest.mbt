// What goes beside a link of a node's words (View::beside's `piece`, runs_link_piece): by the box round all its
// pieces of line, as an old view's card goes by its link (Ctx::rect_of); following it as its words are laid out again,
// as what holds it moves; where it was once its words have no such link.

///|
test "an old view's link across lines: what goes by it goes by the box round all its pieces (Ctx::rect_of), from the start of its lines" {
  let rect : Ref[(Double, Double, Double, Double)?] = Ref(None)
  let t = Tester::new(
    fn(c) {
      c.column(w=Px(160.0), fn() {
        c.rich(linked_runs, size=15.0, on_link_shown=Some(fn(_href, _words, id) { rect.val = c.rect_of(id) })) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=400.0,
  )
  t.frame()
  t.frame()
  let lines = t.run_rects("space.blog 的文档在这里")
  assert_true(lines.length() >= 2, msg="across lines: \{Repr(lines)}")
  let x0 = lines.fold(init=1.0e9, fn(a, r) { dmin(a, r.0) })
  let y0 = lines.fold(init=1.0e9, fn(a, r) { dmin(a, r.1) })
  let x1 = lines.fold(init=-1.0e9, fn(a, r) { dmax(a, r.0 + r.2) })
  let y1 = lines.fold(init=-1.0e9, fn(a, r) { dmax(a, r.1 + r.3) })
  guard rect.val is Some((rx, ry, rw, rh)) else { fail("no rect") }
  // (its first line's piece starts past the words before it: the box from the start of the next)
  assert_true(lines[0].0 > x0 + 0.5, msg="its first piece past its start: \{Repr(lines)}")
  assert_true(
    (rx - x0).abs() < 1.0 && (ry - y0).abs() < 1.0 && (rx + rw - x1).abs() < 1.0 && (ry + rh - y1).abs() < 1.0,
    msg="round all of it: \{Repr(rect.val)} for \{Repr(lines)}",
  )
}

///|
/// A node of `runs` as they are now in a box `w` wide moved by (`dx`, 30) and drawn `scale` as big; a card 50 by 20
/// beside the link starting at run 1 that leads to `href` (runs_link_piece), under it at its start, 4 off, how many
/// times its piece was asked counted in `asked`: the tester, the words' node and the card's.
fn link_card_made(
  runs : @signals.Signal[Array[Run]],
  w : @signals.Signal[Double],
  dx : @signals.Signal[Double],
  asked : Ref[Int],
  scale? : Double = 1.0,
  href? : String = "https://space.blog/docs",
) -> (Tester, @view.NodeId, @view.NodeId) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  t.check_looks(false)
  let ids : Map[String, @view.NodeId] = Map([])
  let words : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(By(fn() { Some(w.get()) }))
      .lines_up(Is(Some(Start)))
      .offset(By(fn() { (dx.get(), 30.0) }))
      .scale(Is(scale))
      |> ignore
      b.box(fn(n) {
        ids["words"] = n.id()
        n
        .words_runs(By(fn() { runs.get() }), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
        |> ignore
        words.val = Some(n)
      })
      |> ignore
    })
    |> ignore
    let n = words.val.unwrap()
    let piece = runs_link_piece(n, 1, href)
    root.box(fn(c) {
      ids["card"] = c.id()
      c
      .width(Is(Some(50.0)))
      .height(Is(Some(20.0)))
      .ground(Is(0x112233FFL))
      .beside(n.id(), side=Bottom, along=Start, offset=4.0, piece=fn(w, h) {
        asked.val = asked.val + 1
        piece(w, h)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, ids["words"], ids["card"])
}

///|
/// Where the link starting at run 1 of node `words` is drawn in the window as it is now, the box round all its pieces of
/// line (each piece as it draws it: view_runs_laid, rich_link_pieces), and where the card is drawn.
fn link_and_card(words : @view.NodeId, card : @view.NodeId) -> ((Double, Double, Double, Double), (Double, Double)) {
  let tree = view_app.val.unwrap()
  let d = tree.drawn_of(words).unwrap()
  let s = tree.drawn_scale(words)
  let (r, lay, _) = view_runs_laid(d.runs, d.words_look, d.runs_look, d.w / s, tree.words_scale_of(d.id))
  let ps = rich_link_pieces(r, lay, 0.0, 0.0).filter(fn(p) { p.0 == 1 })
  let x0 = ps.fold(init=1.0e9, fn(a, p) { dmin(a, p.1) })
  let y0 = ps.fold(init=1.0e9, fn(a, p) { dmin(a, p.2) })
  let x1 = ps.fold(init=-1.0e9, fn(a, p) { dmax(a, p.3) })
  let y1 = ps.fold(init=-1.0e9, fn(a, p) { dmax(a, p.4) })
  let c = tree.drawn_of(card).unwrap()
  ((d.x + x0 * s, d.y + y0 * s, (x1 - x0) * s, (y1 - y0) * s), (c.x, c.y))
}

///|
/// That the card is under the link's box at its start, 4 off (as it is drawn: `what`).
fn card_under(words : @view.NodeId, card : @view.NodeId, what : String) -> (Double, Double) raise {
  let ((lx, ly, _, lh), (cx, cy)) = link_and_card(words, card)
  assert_true((cx - lx).abs() < 0.01 && (cy - (ly + lh + 4.0)).abs() < 0.01, msg="\{what}: card at \{Repr((cx, cy))}, link \{Repr((lx, ly, lh))}")
  (cx, cy)
}

///|
test "a card beside a node's link across lines: under the box round all its pieces, at its start; following it laid out again in another width (on one line), moved, its words said again" {
  let runs = @signals.signal(linked_runs)
  let w = @signals.signal(160.0, same=fn(a, b) { a == b })
  let dx = @signals.signal(40.0, same=fn(a, b) { a == b })
  let asked = Ref(0)
  let (t, words, card) = link_card_made(runs, w, dx, asked)
  let tree = view_app.val.unwrap()
  let ((_, _, _, lh), _) = link_and_card(words, card)
  assert_true(lh > 30.0, msg="across lines: \{lh}")
  let first = card_under(words, card, "as made")
  // (wide enough for it on one line: by that line, past the words before it)
  tree.event(t.time(), fn() { w.set(300.0) })
  t.draw()
  let wider = card_under(words, card, "laid out wider")
  assert_true(wider != first, msg="moved with it: \{Repr(first)} \{Repr(wider)}")
  // (what holds it moved)
  tree.event(t.time(), fn() { dx.set(70.0) })
  t.draw()
  let moved = card_under(words, card, "moved")
  assert_eq(moved.0, wider.0 + 30.0)
  // (its words said again: more before it, the same link starting at run 1)
  tree.event(t.time(), fn() {
    runs.set([plain("先看看这个 "), link("space.blog 的文档在这里", "https://space.blog/docs"), plain(" 然后再说别的。")])
  })
  t.draw()
  let said = card_under(words, card, "its words said again")
  assert_true(said != moved, msg="with its words: \{Repr(moved)} \{Repr(said)}")
  // (a frame with nothing changed: nothing placed, its piece not asked)
  let was = asked.val
  t.draw()
  assert_eq(asked.val, was)
}

///|
test "a card beside a node's link drawn half as big: under the link where it is drawn" {
  let asked = Ref(0)
  let (_, words, card) = link_card_made(
    @signals.signal(linked_runs),
    @signals.signal(160.0),
    @signals.signal(40.0),
    asked,
    scale=0.5,
  )
  card_under(words, card, "half as big") |> ignore
}

///|
test "a card beside a node's link its words no longer have (said again without it, or another at its run): where it was, not by all of the words nor by the other" {
  let runs = @signals.signal(linked_runs)
  let w = @signals.signal(160.0, same=fn(a, b) { a == b })
  let dx = @signals.signal(40.0, same=fn(a, b) { a == b })
  let asked = Ref(0)
  let (t, words, card) = link_card_made(runs, w, dx, asked)
  let tree = view_app.val.unwrap()
  let was = card_under(words, card, "as made")
  let at = fn() {
    let c = tree.drawn_of(card).unwrap()
    (c.x, c.y)
  }
  // (another link at its run)
  tree.event(t.time(), fn() {
    runs.set([plain("看看 "), link("别的地方", "https://space.blog/other"), plain(" 然后再说别的。")])
  })
  t.draw()
  assert_eq(at(), was)
  // (none, and what holds it moved)
  tree.event(t.time(), fn() {
    runs.set([plain("看看 space.blog 的文档在这里 然后再说别的。")])
    dx.set(90.0)
  })
  t.draw()
  assert_eq(at(), was)
  // (back: by it again)
  tree.event(t.time(), fn() { runs.set(linked_runs) })
  t.draw()
  let back = card_under(words, card, "back")
  assert_eq(back.0, was.0 + 50.0)
}

///|
test "a card beside a node's link: its piece asked once each time it is placed, none while nothing is; what has no piece asks none" {
  let runs = @signals.signal(linked_runs)
  let w = @signals.signal(160.0, same=fn(a, b) { a == b })
  let dx = @signals.signal(40.0, same=fn(a, b) { a == b })
  let asked = Ref(0)
  let (t, _, _) = link_card_made(runs, w, dx, asked)
  let tree = view_app.val.unwrap()
  let made = asked.val
  let moves = [50.0, 60.0, 70.0, 80.0, 90.0]
  for x in moves {
    tree.event(t.time(), fn() { dx.set(x) })
    t.draw()
  }
  t.draw()
  t.draw()
  assert_eq((made, asked.val - made), (1, moves.length()))
}
