// What of the window's tree's words is picked, as a page made of nodes reads it (tree_picked.mbt): a quote's pill over
// where the pointer let it go (View::beside by picked_end_piece), shown once it is let go, its press keeping what is
// picked (keeps_picked) and letting it go in its handler (picked_let_go); what each paragraph is of (picked_of); a
// finger's, the app's own item of the system's text menu over it (picked_menu).

///|
/// Two rows of words in a page whose words are picked, 40 apart from 40 down, the first's said of "m1", the second's of
/// "m2", each 300 wide; a pill 40 by 20 over where what is picked ends, 8 off, while a mouse's pick of the tree's words
/// stands, its press putting what it quotes in `took` (what is picked, what of) and letting it go; the page offering
/// 引用 in the system's text menu over a finger's pick of one row's words, doing the same. On `platform`. The Tester, the two rows' words'
/// nodes, and the pill's, once made (`pill`).
fn quote_tester(
  took : Array[(String, Array[String])],
  pill : Ref[@view.NodeId?],
  platform? : Int = 0,
) -> (Tester, @view.NodeId, @view.NodeId) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform~)
  t.check_looks(false)
  let words : Array[@view.NodeId] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.padding(Is((0.0, 40.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      words_picked(page)
      picked_menu(page, fn(p) {
        guard p.of.length() == 1 else { return [] }
        [
          (
            "引用",
            fn() {
              match picked_now() {
                Some(p) => took.push((p.text, p.of))
                None => took.push(("", []))
              }
              picked_let_go()
            },
          ),
          ("复制链接", fn() { took.push(("link", p.of)) }),
        ]
      })
      |> ignore
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

///|
test "words of the tree's a finger held still on: once lifted, the system's text menu over them offers the page's own item after copy and select all, and no pill; chosen, it is done and they are let go" {
  let took : Array[(String, Array[String])] = []
  let pill : Ref[@view.NodeId?] = Ref(None)
  let (t, first, _) = quote_tester(took, pill, platform=2)
  t.press_at(60.0, 51.0)
  t.run_for(long_press_ms)
  t.release(60.0, 51.0)
  t.draw()
  let p = picked_now().unwrap()
  assert_eq((p.text, p.of, p.ends_in, p.finger), ("wide", ["m1"], first, true))
  let (shown, _, _, _, _, can) = t.text_menu()
  assert_true(shown)
  assert_eq(can, @hostapi.text_menu_copy | @hostapi.text_menu_select_all | @hostapi.text_menu_own_item)
  assert_eq(t.text_menu_own(), ["引用", "复制链接"])
  assert_eq(pill.val, None)
  t.key(@hostapi.key_menu_own)
  assert_eq(took, [("wide", ["m1"])])
  assert_eq(t.ctx().selected_text(), "")
  assert_eq(picked_now(), None)
  assert_false(t.text_menu().0)
}

///|
test "words of the tree's a finger picked across two rows: the page offers no item of its own for them, the system's text menu copy and select all alone" {
  let took : Array[(String, Array[String])] = []
  let pill : Ref[@view.NodeId?] = Ref(None)
  let (t, _, _) = quote_tester(took, pill, platform=2)
  t.press_at(60.0, 51.0)
  t.run_for(long_press_ms)
  t.release(60.0, 51.0)
  t.draw()
  assert_eq(t.text_menu().5, @hostapi.text_menu_copy | @hostapi.text_menu_select_all | @hostapi.text_menu_own_item)
  // (all of them: the system's select all)
  t.key(key_code_select_all)
  let p = picked_now().unwrap()
  assert_eq(p.of, ["m1", "m2"])
  let (shown, _, _, _, _, can) = t.text_menu()
  assert_true(shown)
  assert_eq(can, @hostapi.text_menu_copy | @hostapi.text_menu_select_all)
  assert_eq(took.length(), 0)
}

///|
test "words of the tree's that take no press over an old view whose box takes a press there (a page's message over 小屏's shell): a finger held still on them picks the word, the old view's press called off, nothing of it pressed" {
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=2)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      old(b, fn(c) {
        let here = c.id("old box")
        c.on_press(here, fn() { pressed.val = pressed.val + 1 })
        c.box(id=here, w=Fill(1.0), h=Fill(1.0), fn() { c.text("old words") |> ignore }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(page) {
      page.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(300.0))).ground(Is(0xFFFFFFFFL)) |> ignore
      page.padding(Is((0.0, 40.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      words_picked(page)
      page.box(fn(n) {
        n
        .width(Is(Some(300.0)))
        .words_runs(Is(picked_runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  let tree = view_app.val.unwrap()
  assert_true(tree.target_at(60.0, 51.0) is Hosted(_), msg="the press there the old view's")
  t.press_at(60.0, 51.0)
  t.run_for(long_press_ms)
  assert_eq(t.ctx().selected_text(), "wide")
  t.release(60.0, 51.0)
  t.draw()
  assert_eq(picked_now().map(fn(p) { (p.text, p.finger) }), Some(("wide", true)))
  assert_true(t.text_menu().0)
  assert_eq(pressed.val, 0)
}

///|
test "words a finger held still on the space between two words: the word before it picked, as a phone's text picks it; before the first word, the one after it; only space, none" {
  let took : Array[(String, Array[String])] = []
  let pill : Ref[@view.NodeId?] = Ref(None)
  let (t, _, _) = quote_tester(took, pill, platform=2)
  // (on the space after "hello", just past its "o": the space's own, not the start of "wide")
  let glyphs = t.drawn_instances().filter(fn(a) { a[5] == 1.0 && a[1] < 70.0 }).map(fn(a) { (a[0], a[2]) })
  glyphs.sort_by(fn(a, b) { a.0.compare(b.0) })
  let x = glyphs[4].0 + glyphs[4].1 + 0.5
  t.press_at(x, 51.0)
  t.run_for(long_press_ms)
  t.release(x, 51.0)
  t.draw()
  assert_eq(picked_now().map(fn(p) { p.text }), Some("hello"))
  // (the same rule on its own, in the text's units)
  assert_eq(finger_word_at("hello wide", 5), (0, 5))
  assert_eq(finger_word_at("  hi there", 0), (2, 4))
  assert_eq(finger_word_at("   ", 1), (0, 0))
  assert_eq(finger_word_at("hello wide", 7), (6, 10))
}

///|
test "words of the tree's a finger picked: the page's items in the system's text menu in its order, each chosen by its own key, the second doing its own, what is picked kept where it keeps it" {
  let took : Array[(String, Array[String])] = []
  let pill : Ref[@view.NodeId?] = Ref(None)
  let (t, _, _) = quote_tester(took, pill, platform=2)
  t.press_at(60.0, 51.0)
  t.run_for(long_press_ms)
  t.release(60.0, 51.0)
  t.draw()
  assert_eq(t.text_menu_own(), ["引用", "复制链接"])
  t.key(@hostapi.key_menu_own + 1)
  assert_eq(took, [("link", ["m1"])])
  assert_eq(t.ctx().selected_text(), "wide")
  // (one the page does not offer: nothing)
  t.key(@hostapi.key_menu_own + 2)
  assert_eq(took.length(), 1)
  t.key(@hostapi.key_menu_own)
  assert_eq(took, [("link", ["m1"]), ("wide", ["m1"])])
  assert_eq(picked_now(), None)
}
