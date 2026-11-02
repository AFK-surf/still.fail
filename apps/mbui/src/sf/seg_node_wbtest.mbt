// A choice of a few as nodes of the window's tree (seg_node): pressed, the one chosen; a roving group, as
// @kit.toggle_group's: Tab stops at the chosen one alone, ← and → go round its options, Home and End to its ends, each
// chosen with its focus; its arrows its own only while one of its options has the focus; read out as a group of radios.

///|
/// 预览 and 源码 (`chosen` the one chosen, a choice said to it), and a button beside them.
fn seg_tester(chosen : @signals.Signal[Int], said : Array[Int]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).padding(Is((20.0, 20.0, 20.0, 20.0))).gap(Is(20.0)) |> ignore
    seg_node(root, fn() { ["预览", "源码"] }, fn() { chosen.get() }, fn(k) {
      said.push(k)
      chosen.set(k)
    }, item_w=58.0)
    |> ignore
    button_node(root, fn() { "下载" }, fn() {  }) |> ignore
  })
  t.draw()
  t
}

///|
fn seg_radios(t : @ui.Tester) -> Array[(String, @ui.Check?)] {
  t.semantics().filter(fn(s) { s.role == @ui.Role::Radio }).map(fn(s) { (s.label, s.check) })
}

///|
test "a choice of a few as nodes: read out as radios, the chosen one on; pressed, the other chosen" {
  let chosen = @signals.signal(0)
  let said = []
  let t = seg_tester(chosen, said)
  assert_eq(seg_radios(t), [("预览", Some(@ui.Check::On)), ("源码", Some(@ui.Check::Off))])
  t.click(@ui.Role::Radio, label="源码")
  t.draw()
  assert_eq(said, [1])
  assert_eq(seg_radios(t), [("预览", Some(@ui.Check::Off)), ("源码", Some(@ui.Check::On))])
}

///|
test "a choice of a few as nodes, a roving group: Tab to the chosen one alone; → and ← round it, Home and End, each chosen with its focus; Tab on to the button beside it, its arrows none of its own" {
  let chosen = @signals.signal(1)
  let said = []
  let t = seg_tester(chosen, said)
  t.key(@ui.key_tab)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("源码"), msg="Tab: the chosen one")
  t.key(@ui.key_code_right)
  t.draw()
  assert_eq((chosen.get(), t.focused().map(fn(s) { s.label })), (0, Some("预览")), msg="→ from the last: round to the first")
  t.key(@ui.key_code_left)
  t.draw()
  assert_eq((chosen.get(), t.focused().map(fn(s) { s.label })), (1, Some("源码")), msg="← from the first: round to the last")
  t.key(@ui.key_code_home)
  t.draw()
  assert_eq(chosen.get(), 0, msg="Home")
  t.key(@ui.key_code_end)
  t.draw()
  assert_eq(chosen.get(), 1, msg="End")
  t.key(@ui.key_tab)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("下载"), msg="Tab on: the button beside it")
  let before = said.length()
  t.key(@ui.key_code_right)
  t.key(@ui.key_code_home)
  t.draw()
  assert_eq((chosen.get(), said.length()), (1, before), msg="its arrows none of its own, the focus not in it")
}

///|
/// 预览 and 源码 (`chosen` the one chosen, a choice said to it) in a line `room()` wide, 44 high (a bar's), a window wide
/// enough for a pick beside it (not a sheet), what is presented drawn by the window's tree and kept by the host as the
/// app's is (presented, in an old view over all of it as the app's frame hosts it: what has gone let go of).
fn seg_room_tester(chosen : @signals.Signal[Int], said : Array[Int], room : @signals.Signal[Double]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=900.0, h=400.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
    root.box(fn(line) {
      line.row(Is(true)).width(By(fn() { Some(room.get()) })).height(Is(Some(44.0))) |> ignore
      // (in a box of its own in the line, laid out down, as a bar's row shows it: image_tools' row.show)
      line.box(fn(r) {
        r.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        seg_node(r, fn() { ["预览", "源码"] }, fn() { chosen.get() }, fn(k) {
          said.push(k)
          chosen.set(k)
        }, item_w=58.0)
        |> ignore
      })
      |> ignore
    })
    |> ignore
    @ui.old(root, fn(c) { presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn seg_shown(t : @ui.Tester, role : @ui.Role) -> Array[@ui.SemNode] {
  t.semantics().filter(fn(s) { s.role == role && !s.hidden })
}

///|
test "a choice of a few as nodes short of room: its track as wide as the room, its options sharing it; less, the chosen one alone with a chevron, the other in a pick beside it; the room back, side by side again, the one picked chosen and Tab's stop" {
  let chosen = @signals.signal(0)
  let said = []
  let room = @signals.signal(400.0)
  let t = seg_room_tester(chosen, said, room)
  let group = fn() { seg_shown(t, RadioGroup).map(fn(s) { s.rect.2 }) }
  let widths = fn() { seg_shown(t, Radio).map(fn(s) { s.rect.2 }) }
  // (its room: its columns whole, 58 each, its track 3 round them, 2 between)
  assert_eq((group(), widths()), ([124.0], [58.0, 58.0]), msg="whole")
  // (as high as its options with its pad round them, in a line higher than that: not stretched to it)
  assert_eq(seg_shown(t, RadioGroup).map(fn(s) { s.rect.3 }), [36.0], msg="its track's height")
  // (short: as wide as the room, its options what is in it less its sides and their gap, alike)
  room.set(110.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq((group(), widths()), ([110.0], [51.0, 51.0]), msg="sharing the room")
  // (too short for both side by side: the chosen one's words alone, pressed a pick of both)
  room.set(60.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(
    (widths(), seg_shown(t, Button).map(fn(s) { (s.label, s.rect.2, s.expanded) })),
    ([], [("预览", 54.0, Some(false))]),
    msg="the chosen one alone, its pick shut",
  )
  // (the button itself, by its id: under its pick, a modal layer, it is hidden while that is open)
  let opener = seg_shown(t, Button)[0]
  let (x, y, w, h) = opener.rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(
    t.semantics().filter(fn(s) { s.id == opener.id }).map(fn(s) { (s.label, s.expanded, s.hidden) }),
    [("预览", Some(true), true)],
    msg="its pick open, over it",
  )
  let items = t.semantics().filter(fn(s) { !s.hidden && (s.role == MenuItemRadio || s.role == MenuItem) })
  assert_eq(items.map(fn(s) { (s.label, s.check) }), [("预览", Some(@ui.Check::On)), ("源码", Some(@ui.Check::Off))], msg="its pick: \{items}")
  let (x, y, w, h) = items[1].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(
    (said, seg_shown(t, Button).map(fn(s) { (s.label, s.expanded) })),
    ([1], [("源码", Some(false))]),
    msg="源码 picked, its pick shut: \{said} \{seg_shown(t, Button)} \{t.semantics().filter(fn(s) { s.role == Button })}",
  )
  // (the room back: side by side, 源码 on, Tab's stop)
  room.set(400.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(
    seg_shown(t, Radio).map(fn(s) { (s.label, s.check, s.rect.2) }),
    [("预览", Some(@ui.Check::Off), 58.0), ("源码", Some(@ui.Check::On), 58.0)],
    msg="side by side again",
  )
  t.key(@ui.key_tab)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("源码"), msg="Tab: the one picked")
}

///|
test "a choice of a few as nodes, the system's size of words changed while it shows: its columns as wide as its words are then" {
  let chosen = @signals.signal(0)
  let room = @signals.signal(400.0)
  let t = seg_room_tester(chosen, [], room)
  let widths = fn() { seg_shown(t, Radio).map(fn(s) { s.rect.2 }) }
  assert_eq(widths(), [58.0, 58.0], msg="item_w")
  t.set_font_scale(2.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let c = @ui.current()
  let w = choice_words_w(c, "预览", c.sp(theme().t.ui), weight=500) + 2.0 * segmented_in
  assert_true(w > 58.0, msg="its words wider than item_w at 2: \{w}")
  assert_eq(widths(), [w, w], msg="as wide as its words")
}

///|
test "a choice of a few as nodes short of room, its words made smaller to fit (the system's size of words at 2): each option as fitted, its words whole in it at that size, the thumb under the chosen one as wide" {
  let chosen = @signals.signal(1)
  let room = @signals.signal(400.0)
  let t = seg_room_tester(chosen, [], room)
  t.set_font_scale(2.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let c = @ui.current()
  let size = c.sp(theme().t.ui)
  let words = choice_words_w(c, "预览", size, weight=500)
  // (room for their words at 0.8 of their size with the least either side: less than whole, more than the smallest)
  let inner = 0.8 * 2.0 * words + 4.0 * segmented_least
  let f = fitted(c, ["预览", "源码"], inner, theme().t.ui, 500, segmented_in, segmented_least)
  guard f.fit is Smaller(k) else { fail("not made smaller: \{f.fit}") }
  room.set(inner + 2.0 * segmented_pad + segmented_gap)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let radios = seg_shown(t, Radio)
  assert_eq(radios.map(fn(s) { s.rect.2 }), f.widths, msg="each as fitted")
  // (each one's words whole, at their size made smaller, inside its option)
  for r in radios {
    let (ox, _, ow, _) = r.rect
    let drawn = t.words().filter(fn(w) { w.0 == r.label })
    let least = choice_words_w(c, r.label, size * k, weight=if r.check == Some(@ui.Check::On) { 500 } else { 400 })
    assert_true(
      drawn.length() == 1 && drawn[0].3 >= least - 0.5 && drawn[0].1 >= ox - 0.5 && drawn[0].1 + drawn[0].3 <= ox + ow + 0.5,
      msg="\{r.label} whole in its option \{r.rect}, \{least} at \{k}: \{drawn}",
    )
  }
  // (the thumb: the theme's lifted, as high as an option, where the chosen one is and as wide)
  let thumb = t.drawn_rects().filter(fn(d) { d.4 == @ui.tree_theme().lifted && d.3 == segmented_h })
  let on = radios.filter(fn(s) { s.check == Some(@ui.Check::On) })
  assert_eq(on.map(fn(s) { s.label }), ["源码"])
  assert_eq(thumb.map(fn(d) { (d.0, d.2) }), [(on[0].rect.0, on[0].rect.2)], msg="the thumb under 源码: \{thumb}")
}
