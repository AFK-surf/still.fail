///|
test "a retained chat row shows selection from its first frame and follows it without being rebuilt" {
  for platform in [0, 2] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    let selected = @signals.signal(true)
    let made = Ref(0)
    let item = { ..sample_chat(0), title: "A chat", ago: "5 minutes ago", full: "A moment ago" }
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=200.0, platform~)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      made.val += 1
      chat_row_node(root, @sfbase.sample_source, tips, fn() { item }, "agents", fn() { selected.get() }, Side, fn() { 0 }) |> ignore
    })
    t.draw()
    let lit = fn() {
      t.drawn_rects().filter(fn(r) { r.2 > 100.0 && r.3 > 30.0 && r.4 == @sf.theme().p.selected }).length()
    }
    assert_eq(lit(), 1, msg="selected when made, platform \{platform}")
    selected.set(false)
    t.run_for(left_lit_ms + left_fade_ms + @sf.dur_ms)
    assert_eq(lit(), 0, msg="selection left, platform \{platform}")
    selected.set(true)
    t.run_for(@sf.dur_ms)
    assert_eq(lit(), 1, msg="selected again, platform \{platform}")
    assert_eq(made.val, 1)
  }
}

///|
test "a mouse entering a retained chat row shows its background and time with its archive action" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let item = { ..sample_chat(0), title: "A chat", ago: "5 minutes ago", full: "A moment ago" }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=200.0, platform=0, pointing=Mouse)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
    let tips = @sf.TipLayer::new(fn() { Some(popup) })
    chat_row_node(root, @sfbase.sample_source, tips, fn() { item }, "agents", fn() { false }, Side, fn() { 0 }) |> ignore
  })
  t.draw()
  assert_true(t.find(item.ago) is None)
  let (x, y, w, h) = t.get(Link, label=item.title).rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(@sf.dur_ms)
  assert_true(t.find(item.ago) is Some(_), msg="the row says when while pointed at")
  assert_true(t.query(Button, label=@sf.t("web-main.chat.archiveNamed", args=[("title", item.title)])) is Some(_))
  assert_true(t.drawn_rects().iter().any(fn(r) { r.2 > 100.0 && r.3 > 30.0 && r.4 == @sf.theme().p.hover }), msg="the row's hover background")
  t.move_to(319.0, 199.0)
  t.run_for(@sf.dur_ms)
  assert_true(t.find(item.ago) is None)
  t.assert_idle()
}

///|
test "a finger's chat row keeps its ground a while after its chat only where the list was covered by it" {
  for at in [@sf.ListAt::Side, Whole] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    // (which chat is in view: 0, 1, or none, -1)
    let open = @signals.signal(0)
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=400.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      for i in 0..<2 {
        let item = { ..sample_chat(i), title: "Chat \{i}" }
        chat_row_node(root, @sfbase.sample_source, tips, fn() { item }, "agents", fn() { open.get() == i }, at, fn() {
          0
        })
        |> ignore
      }
    })
    t.draw()
    let ink = @sf.theme().p.selected & 0xFFFFFF00L
    let lit = fn() {
      t.drawn_rects().filter(fn(r) { r.2 > 100.0 && r.3 > 30.0 && (r.4 & 0xFFFFFF00L) == ink && (r.4 & 0xFFL) > 0L }).length()
    }
    assert_eq(lit(), 1)
    // another chat opened in its place, or gone back to the list
    open.set(1)
    t.run_for(@sf.dur_ms)
    let switched = lit()
    open.set(-1)
    t.run_for(@sf.dur_ms)
    let back = lit()
    if at == Side {
      // beside the chat: as a mouse's rows
      assert_eq((switched, back), (1, 0), msg="beside the chat")
    } else {
      // across the whole screen: the row gone back from stays lit as its page slides off
      assert_eq(back, 1, msg="across the whole screen, gone back")
      t.run_for(left_lit_ms + left_fade_ms)
      assert_eq(lit(), 0)
    }
  }
}

///|
test "a finger's row pressed beside the chat goes from its press's ground to the selected one's, never through none" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let open = @signals.signal(0)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=400.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
    let tips = @sf.TipLayer::new(fn() { Some(popup) })
    for i in 0..<2 {
      let item = { ..sample_chat(i), title: "Chat \{i}" }
      chat_row_node(root, @sfbase.sample_source, tips, fn() { item }, "agents", fn() { open.get() == i }, Side, fn() {
        0
      })
      |> ignore
    }
  })
  t.draw()
  let (x, y, w, h) = t.get(Link, label="Chat 1").rect
  // (its ground's ink: none drawn, 0)
  let ground = fn() {
    match t.drawn_rects().filter(fn(r) { r.2 > 100.0 && r.3 > 30.0 && r.1 >= y - 1.0 && r.1 + r.3 <= y + h + 1.0 }) {
      [r, ..] => r.4 & 0xFFL
      [] => 0L
    }
  }
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.tap_indication_ms)
  assert_true(ground() > 0L, msg="pressed")
  // let go, its chat not yet in view: its press's ground going
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.frame()
  assert_true(ground() > 0L, msg="let go")
  // its chat in view: the selected one's ground coming, there over dur_ms
  open.set(1)
  t.frame()
  assert_true(ground() > 0L, msg="its chat in view")
  t.run_for(@sf.dur_ms)
  assert_eq(ground(), 0xFFL)
}

///|
test "a chat row taken for another chat, as its list is laid out, sets no way going: what it shows is put as it would be made anew" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let first = { ..sample_chat(0), title: "A chat", ago: "5 minutes ago", full: "A moment ago" }
  let other = { ..sample_chat(1), title: "Another chat", ago: "an hour ago", full: "An hour ago" }
  let item = @signals.signal(first)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=200.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
    let tips = @sf.TipLayer::new(fn() { Some(popup) })
    chat_row_node(root, @sfbase.sample_source, tips, fn() { item.get() }, "agents", fn() { false }, Side, fn() { 0 }) |> ignore
  })
  t.draw()
  t.run_for(@sf.dur_ms)
  // (the row given another chat, nothing else changed: as a list's block is given another key as the list scrolls)
  let said = @motion.ways_said()
  item.set(other)
  t.frame()
  assert_eq(@motion.ways_said() - said, 0, msg="ways set going as the row was taken for another chat")
  assert_true(t.find(other.title) is Some(_))
  assert_true(t.moving().length() == 0, msg="\{Repr(t.moving())}")
  assert_true(
    !t.drawn_rects().iter().any(fn(r) { r.2 > 100.0 && r.3 > 30.0 && r.4 == @sf.theme().p.selected }),
    msg="no ground of the chat in view on a row not in view",
  )
}
