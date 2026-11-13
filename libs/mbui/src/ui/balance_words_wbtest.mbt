// Words broken where their lines come out even (TextPatch `balance`): an old view's (Ctx::text) and a node's of the
// window's tree (View::words, style_words) laid out, measured and drawn alike, by the same balanced.

///|
/// The same words drawn by an old view at (0, 0) and by a node 200 down, each `w` wide (as `width` says now), in a
/// style that balances them where `balance` says; how tall the node is laid out.
fn balance_pair(words : String, width : @signals.Signal[Double], balance : Bool) -> (Tester, () -> Double) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  t.check_looks(false)
  let style = text_style(size=Body, balance~)
  let id : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.width(By(fn() { Some(width.get()) })).height(Is(Some(200.0))) |> ignore
      old(h, fn(c) { c.box(w=Px(width.get()), fn() { c.text(words, style~, color=0x333333FFL) |> ignore }) |> ignore }).grow(
        Is(1.0),
      )
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b.width(By(fn() { Some(width.get()) })).lines_up(Is(Some(Start))) |> ignore
      b.box(fn(n) {
        id.val = Some(n.id())
        n.words(Is(words), ink=0x333333FFL, look=style_words(style)) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = view_app.val.unwrap()
  (t, fn() { tree.drawn_of(id.val.unwrap()).unwrap().h })
}

///|
test "balance: an old view's words and a node's in the same style broken alike, at the same places, drawn alike; laid out again alike as their width and the system's size of words change; unbalanced, both greedy, elsewhere" {
  // (8 a letter at the body size: greedy at 150, "abcdef ghijkl mnop" and "q" alone; balanced, "abcdef ghijkl", "mnop q")
  let words = "abcdef ghijkl mnop q"
  let lines = fn(gs : Array[(Double, Double, Int64)]) {
    let ys = []
    for g in gs {
      if !ys.contains(g.1) {
        ys.push(g.1)
      }
    }
    ys.length()
  }
  let last_count = fn(gs : Array[(Double, Double, Int64)]) {
    let last_y = gs.fold(init=0.0, fn(m, g) { if g.1 > m { g.1 } else { m } })
    gs.filter(fn(g) { g.1 == last_y }).length()
  }
  // (balanced, one tree tested through before another is made: a Tester made lets the one before go)
  let width = @signals.signal(150.0)
  let (t, tall) = balance_pair(words, width, true)
  let (old, new) = runs_drawn(t)
  assert_true(old.length() > 10, msg="the old one drawn: \{old.length()}")
  assert_eq(new, old)
  let at_150 = lines(new)
  assert_true(at_150 >= 2, msg="more than a line at 150: \{at_150}")
  let balanced_150 = new
  let tall_150 = tall()
  // (wider: laid out again, alike, on no more lines)
  width.set(260.0)
  t.draw()
  let (old, new) = runs_drawn(t)
  assert_eq(new, old, msg="at 260")
  assert_true(lines(new) <= at_150 && tall() <= tall_150, msg="no more lines when wider: \{lines(new)}, \{tall()}")
  // (back to 150, the system's words larger: laid out again, alike, taller)
  width.set(150.0)
  t.set_font_scale(1.3)
  t.draw()
  let (old, new) = runs_drawn(t)
  assert_eq(new, old, msg="larger words")
  assert_true(tall() > tall_150, msg="taller with larger words: \{tall()} over \{tall_150}")
  // (greedy, the same words and width: alike too, broken elsewhere, its last line shorter)
  let (tg, _) = balance_pair(words, @signals.signal(150.0), false)
  let (gold, gnew) = runs_drawn(tg)
  assert_eq(gnew, gold, msg="greedy: alike too")
  assert_true(gnew != balanced_150, msg="balanced broken elsewhere than greedy")
  assert_true(last_count(balanced_150) > last_count(gnew), msg="the balanced last line longer than the greedy one")
}
