// What of the window's tree's words is picked, as a page made of nodes reads it (tree_picked.mbt): a quote's pill over
// where the pointer let it go (View::beside by picked_end_piece), shown once it is let go, its press keeping what is
// picked (keeps_picked) and letting it go in its handler (picked_let_go); what each paragraph is of (picked_of).

///|
/// Two rows of words in a page whose words are picked, 40 apart from 40 down, the first's said of "m1", the second's of
/// "m2", each 300 wide; a pill 40 by 20 over where what is picked ends, 8 off, while a mouse's pick of the tree's words
/// stands, its press putting what it quotes in `took` (what is picked, what of) and letting it go. The Tester, the two
/// rows' words' nodes, and the pill's, once made (`pill`).
fn quote_tester(
  took : Array[(String, Array[String])],
  pill : Ref[@view.NodeId?],
) -> (Tester, @view.NodeId, @view.NodeId) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  let words : Array[@view.NodeId] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.padding(Is((0.0, 40.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      words_picked(page)
      for of in ["m1", "m2"] {
        page.box(fn(row) {
          picked_of(row, of) |> ignore
          row.height(Is(Some(40.0))) |> ignore
          row.box(fn(n) {
            words.push(n.id())
            n
            .width(Is(Some(300.0)))
            .words_runs(Is(picked_runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      page.show(fn() { picked_now() is Some(p) && !p.finger }, fn(holds) {
        guard @signals.untracked(fn() { picked_now() }) is Some(p) else { return }
        holds.box(fn(b) {
          pill.val = Some(b.id())
          keeps_picked(b)
          .width(Is(Some(40.0)))
          .height(Is(Some(20.0)))
          .ground(Is(0x112233FFL))
          .says(Is(Some(@view.said(Button, label="引用"))))
          .beside(p.ends_in, side=Top, offset=8.0, piece=picked_end_piece(p))
          .on_press(fn() {
            match picked_now() {
              Some(p) => took.push((p.text, p.of))
              None => took.push(("", []))
            }
            picked_let_go()
          })
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, words[0], words[1])
}

///|
test "words of the tree's dragged over with the mouse: what is picked read by a node once let go (its words, what they are of, the node it ends in), none while dragged; a pill beside where it ends; pressed, what is picked kept, and let go by its handler" {
  let took : Array[(String, Array[String])] = []
  let pill : Ref[@view.NodeId?] = Ref(None)
  let (t, first, _) = quote_tester(took, pill)
  let tree = view_app.val.unwrap()
  // (dragged over all the first row's words, held: none yet)
  t.fake.time = t.time()
  finger(0, 1.0, 51.0)
  t.fake.time = t.fake.time + input_step_ms
  finger(1, 300.0, 51.0)
  t.frame_at(t.fake.time)
  assert_eq(t.ctx().selected_text(), "hello wide world")
  assert_eq(picked_now(), None)
  assert_eq(pill.val, None)
  // (let go)
  t.fake.time = t.fake.time + input_step_ms
  finger(2, 300.0, 51.0)
  t.frame_at(t.fake.time)
  let p = picked_now().unwrap()
  assert_eq((p.text, p.of, p.ends_in, p.finger), ("hello wide world", ["m1"], first, false))
  // (the pill: its middle at the right end of what is drawn picked, its foot 8 over its line's top)
  let id = pill.val.unwrap()
  let d = tree.drawn_of(id).unwrap()
  let (px, py, pw, ph) = (d.x, d.y, d.w, d.h)
  let drawn = picked_drawn(t)
  assert_eq(drawn.length(), 1)
  let (rx, ry, rw, _) = drawn[0]
  assert_true(
    (px + pw / 2.0 - (rx + rw)).abs() < 0.01 && (py + ph - (ry - 8.0)).abs() < 0.01,
    msg="pill at \{Repr((px, py, pw, ph))}, picked drawn at \{Repr(drawn[0])}",
  )
  // (pressed: what is picked kept as it goes down; its handler took it and let it go)
  let (cx, cy) = (px + pw / 2.0, py + ph / 2.0)
  t.fake.time = t.fake.time + double_click_ms
  finger(0, cx, cy)
  t.frame_at(t.fake.time)
  assert_eq(t.ctx().selected_text(), "hello wide world")
  t.fake.time = t.fake.time + input_step_ms
  finger(2, cx, cy)
  t.frame_at(t.fake.time)
  assert_eq(took, [("hello wide world", ["m1"])])
  assert_eq(t.ctx().selected_text(), "")
  assert_eq(picked_now(), None)
  assert_eq(picked_drawn(t).length(), 0)
}

///|
test "words of the tree's dragged over from one row into the next: what each is of, in order, it ending in the second; a press elsewhere lets it go" {
  let took : Array[(String, Array[String])] = []
  let pill : Ref[@view.NodeId?] = Ref(None)
  let (t, _, second) = quote_tester(took, pill)
  let next = dragged_at(t, 1.0, 51.0, 300.0, 91.0, t.time(), true)
  t.frame_at(next)
  let p = picked_now().unwrap()
  assert_eq((p.text, p.of, p.ends_in), ("hello wide world\nhello wide world", ["m1", "m2"], second))
  // (pressed where nothing keeps it: let go)
  let next = dragged_at(t, 350.0, 250.0, 350.0, 250.0, next + double_click_ms, true)
  t.frame_at(next)
  assert_eq(picked_now(), None)
  assert_eq(took.length(), 0)
}
