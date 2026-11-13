// A node's words with links in them (runs_links) are a ground, as an old view's paragraph is (rooms.mbt's head): no
// target of the room's rule, links and all, so none of their own is checked and none cut from a button beside them;
// a node taking a finger where it says (View::takes) and pressed is a target as ever.

///|
/// A button 120 by 36 (a keyboard and mouse's least: platform 0) and under it, 160 wide, a node of `runs` with its
/// links pressed (runs_links); the tester and the button.
fn ground_tester(runs : Array[Run]) -> (Tester, @view.NodeId) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=0)
  t.check_looks(false)
  let button : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(160.0))).lines_up(Is(Some(Start))) |> ignore
      b.box(fn(k) {
        button.val = Some(k.id())
        k
        .width(Is(Some(120.0)))
        .height(Is(Some(36.0)))
        .presses(Is(true))
        .says(Is(Some(@view.said(Button, label="好"))))
        .on_press(fn() {  })
        |> ignore
      })
      |> ignore
      b.box(fn(n) {
        n
        .words_runs(Is(runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
        |> ignore
        runs_links(n, fn() { runs }, fn(_) {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, button.val.unwrap())
}

///|
test "words with no link, a link on one line and one across three are no target: the button over them keeps its room whole" {
  for k, runs in [
    [plain("看看 space.blog 的文档在这里，然后再说别的。")],
    [plain("看 "), link("文档", "https://space.blog/docs"), plain(" 吧")],
    [plain("看看 "), link("space.blog 的文档在这里，然后再说别的事情。还有更多", "https://space.blog/docs"), plain(" 吧")],
  ] {
    let (t, button) = ground_tester(runs)
    let boxes = view_app.val.unwrap().press_boxes()
    // (the button alone, as big as it is drawn)
    assert_eq(boxes.map(fn(b) { (b.0 == button, b.1) }), [(true, (0.0, 0.0, 120.0, 36.0))], msg="case \{k}")
    assert_eq(t.tree_room_faults(), [], msg="case \{k}")
  }
}

///|
test "a link across three lines is still pressed on each piece" {
  let went = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=0)
  t.check_looks(false)
  let runs = [plain("看看 "), link("space.blog 的文档在这里，然后再说别的事情。还有更多", "https://space.blog/docs"), plain(" 吧")]
  let id : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(n) {
      id.val = Some(n.id())
      n
      .width(Is(Some(160.0)))
      .words_runs(Is(runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
      |> ignore
      runs_links(n, fn() { runs }, fn(h) { went.push(h) }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = view_app.val.unwrap()
  let d = tree.drawn_of(id.val.unwrap()).unwrap()
  let (r, lay, _) = view_runs_laid(d.runs, d.words_look, d.runs_look, d.w, tree.words_scale_of(d.id))
  let pieces = rich_link_pieces(r, lay, d.x, d.y)
  assert_true(pieces.length() >= 3, msg="\{pieces.length()} pieces")
  for p in pieces {
    t.tap((p.1 + p.3) / 2.0, (p.2 + p.4) / 2.0)
  }
  assert_eq(went.length(), pieces.length())
}

///|
test "a node pressed that takes a finger where it says (View::takes: all of it, or none) is a target while it takes one" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=0)
  t.check_looks(false)
  let open = @signals.signal(true)
  set_view_app(fn(root) {
    root.box(fn(k) {
      k
      .width(Is(Some(120.0)))
      .height(Is(Some(44.0)))
      .presses(Is(true))
      .says(Is(Some(@view.said(Button, label="栏"))))
      .on_press(fn() {  })
      .takes(fn(w, h, _) { if open.get() { [(0.0, 0.0, w, h)] } else { [] } })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(view_app.val.unwrap().press_boxes().map(fn(b) { b.1 }), [(0.0, 0.0, 120.0, 44.0)])
  assert_eq(t.tree_room_faults(), [])
}
