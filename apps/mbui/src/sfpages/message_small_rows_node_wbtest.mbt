// The small rows of a chat's list and the lines under the viewer's message as nodes (message_small_rows_node.mbt),
// and a row's room (message_row_node.mbt): drawn as the old view draws them (set side by side while they were made:
// words, rectangles, lines and shapes the same at 760 and 390 wide), held here by how their parts stand.

///|
/// A runtime a message waits on.
fn small_rows_install(
  state : String,
  action? : String = "安装",
  note? : String = "",
  percent? : Double,
  detail? : String = "",
) -> Install {
  { runtime: "codex", state, title: "Willow 上没有 codex", note, action, percent, detail }
}

///|
/// What `build` makes as nodes in a column `w` wide, with the window's tips; drawn once.
fn small_rows_new(w : Double, build : (@view.View, @sf.TipLayer) -> Unit) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let col = root.box(fn(v) { v.width(Is(Some(w))) |> ignore })
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      build(col, tips)
    },
    w=w + 40.0,
    h=400.0,
    platform=0,
  )
  t.draw()
  t
}

///|
/// Where the lines drawn span across (from, to).
fn small_rows_lines_across(t : @ui.Tester) -> (Double, Double) {
  let xs = t.drawn_lines().map(fn(l) { l.0 })
  let lo = xs.fold(init=@double.infinity, fn(a, b) { if b < a { b } else { a } })
  let hi = xs.fold(init=-@double.infinity, fn(a, b) { if b > a { b } else { a } })
  (lo, hi)
}

///|
test "the small rows as nodes: the line over what is new between its rules, a page coming its spinner in the middle, why the older failed in its column, an empty chat's words in the middle" {
  for w in [760.0, 390.0] {
    let at = "width \{w}"
    let t = small_rows_new(w, fn(v, _) { unread_line_node(v) |> ignore })
    t.run_for(@ui.move_most_ms)
    let (x, y, ww, h) = t.rect_of(@sf.t("web-main.chat.unreadLine")).unwrap()
    let rules = t.drawn_rects().filter(fn(r) { r.3 <= 1.0 && r.2 > 0.0 })
    assert_eq(rules.length(), 2, msg=at)
    assert_true(rules[0].0 + rules[0].2 <= x && rules[1].0 >= x + ww, msg=at)
    assert_true((rules[0].1 - (y + h / 2.0)).abs() <= 1.0, msg=at)
    assert_true((x + ww / 2.0 - w / 2.0).abs() <= 1.0, msg=at)
    assert_eq(t.audit(), [], msg=at)
    for older in [true, false] {
      let t = small_rows_new(w, fn(v, _) { pages_coming_node(v, fn() { older }) |> ignore })
      t.run_for(@ui.move_most_ms)
      let (lo, hi) = small_rows_lines_across(t)
      assert_true(lo < hi && ((lo + hi) / 2.0 - w / 2.0).abs() <= 1.0, msg="\{at}, older \{older}")
      assert_eq(t.audit(), [], msg=at)
    }
    let why = "网络断开了，稍后会再试一次，这一句话写得长一些好让它在窄的时候换行，再长一些，再长一些，再长一些"
    let t = small_rows_new(w, fn(v, _) { older_failed_node(v, fn() { why }) |> ignore })
    t.run_for(@ui.move_most_ms)
    let (x, _, ww, _) = t.rect_of(@sf.t("web-main.chat.olderFailed", args=[("why", why)])).unwrap()
    assert_true(x >= 0.0 && x + ww <= w, msg=at)
    assert_eq(t.audit(), [], msg=at)
    let t = small_rows_new(w, fn(v, _) { chat_empty_node(v) |> ignore })
    t.run_for(@ui.move_most_ms)
    let (x, _, ww, _) = t.rect_of(@sf.t("web-main.chat.empty")).unwrap()
    assert_true((x + ww / 2.0 - w / 2.0).abs() <= 1.0, msg=at)
    assert_eq(t.audit(), [], msg=at)
  }
}

///|
test "where the chat stands, as a line: led by its icon in its column, then what follows it; done with nothing said its word; with no lead its words alone from the start" {
  let lead = @signals.signal("need")
  let rest = @signals.signal("确认是否合并这个分支")
  let words = @signals.signal("需要你：确认是否合并这个分支")
  let t = small_rows_new(390.0, fn(v, _) {
    chat_state_line_node(v, fn() { words.get() }, fn() { lead.get() }, fn() { rest.get() }) |> ignore
  })
  t.run_for(@ui.move_most_ms)
  // (the bell in its column, the words after it)
  let (x, _, _, _) = t.rect_of("确认是否合并这个分支").unwrap()
  assert_true(t.drawn_shapes().length() > 0)
  let icon_end = t.drawn_shapes().fold(init=0.0, fn(a, s) { if s.0 + s.2 > a { s.0 + s.2 } else { a } })
  assert_true(x >= icon_end - 2.0 * state_icon_out, msg="\{x} \{icon_end}")
  assert_eq(t.audit(), [])
  // done with nothing said: its word after the check
  lead.set("done")
  rest.set("")
  words.set("已完成")
  t.run_for(@ui.move_most_ms)
  assert_true(t.rect_of(@sf.t("web-main.status.done")) is Some((dx, _, _, _)) && dx > 0.0)
  // no lead: its words alone, from the start
  lead.set("")
  words.set("正在等你的下一句话")
  t.run_for(@ui.move_most_ms)
  assert_true(t.rect_of("正在等你的下一句话") is Some((0.0, _, _, _)))
  assert_eq(t.drawn_shapes().length(), 0)
  assert_eq(t.audit(), [])
}

///|
test "the line under a message waiting for a runtime: a red mark while it is missing, its action underlined under the pointer, the line pressed installs it; installing, it turns, its percent said, faded, pressed no more" {
  let calls : Array[String] = []
  let src = @sfbase.made_source(call=fn(name, _, done) {
    calls.push(name)
    done(Ok(Json::null()))
  })
  let b = @signals.signal(small_rows_install("missing"))
  let t = small_rows_new(390.0, fn(v, tips) {
    v.box(fn(m) {
      @sf.style_node(m, fn() { mine_column })
      blocked_line_node(m, src, tips, fn() { "st" }, fn() { b.get() }) |> ignore
    })
    |> ignore
  })
  t.run_for(@ui.move_most_ms)
  let red = @sf.theme().p.red
  let marks = fn() { t.drawn_rects().filter(fn(r) { r.2 == r.3 && r.2 > 6.0 && r.4 >> 8 == red >> 8 }).length() }
  assert_eq(marks(), 1)
  assert_true(t.find("!") is Some(_))
  // under the pointer: its action underlined
  let underlines = fn() { t.drawn_rects().filter(fn(r) { r.3 <= 1.0 }).length() }
  assert_eq(underlines(), 0)
  let (x, y, aw, ah) = t.rect_of("安装").unwrap()
  t.move_to(x + aw / 2.0, y + ah / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(underlines(), 1)
  // pressed: installed on its station
  t.tap(x + aw / 2.0, y + ah / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(calls, ["software.update"])
  assert_eq(t.audit(), [])
  // installing, as the core says: turning, how far, no red mark, nothing to press
  b.set(small_rows_install("installing", action="", percent=42.0))
  t.run_for(@ui.move_most_ms)
  assert_eq(marks(), 0)
  assert_true(t.drawn_lines().length() > 0)
  assert_true(t.find("Willow 上没有 codex 42%") is Some(_))
  assert_true(t.find("安装") is None)
  assert_eq(t.audit(), [])
}

///|
test "the line under a message its agents have yet to take: a small spinner and its words at the column's end" {
  let t = small_rows_new(390.0, fn(v, _) {
    v.box(fn(m) {
      @sf.style_node(m, fn() { mine_column })
      agent_waiting_node(m) |> ignore
    })
    |> ignore
  })
  t.run_for(@ui.move_most_ms)
  let (x, _, ww, _) = t.rect_of(@sf.t("web-main.chat.waitingAgent")).unwrap()
  assert_true((x + ww - 390.0).abs() <= 1.0)
  let (_, hi) = small_rows_lines_across(t)
  assert_true(hi <= x)
  assert_eq(t.audit(), [])
}

///|
test "正在发送 shows sending_shows_ms after it was sent, not before; a line made again after that shows it at once; while its words fly here none of it shows; sent at another moment, from that one" {
  let on = @signals.signal(true)
  let flying = @signals.signal(false)
  let since = @signals.signal(0.0)
  let t = small_rows_new(390.0, fn(v, _) {
    since.set(v.cause_at())
    v.show(fn() { on.get() }, fn(s) {
      s.box(fn(m) {
        @sf.style_node(m, fn() { mine_column })
        sending_line_node(m, fn() { @sf.t("web-main.chat.sending") }, fn() { None }, fn() { since.get() }, fn() {
          flying.get()
        })
        |> ignore
      })
      |> ignore
    })
  })
  let sending = @sf.t("web-main.chat.sending")
  let seen = fn() {
    match t.words().iter().find_first(fn(w) { w.0 == sending }) {
      Some(w) => w.5
      None => -1.0
    }
  }
  // its room kept, nothing of it seen
  assert_eq(seen(), 0.0)
  t.run_for(sending_shows_ms)
  assert_eq(seen(), 1.0)
  // let go and made again: from when it was sent, not from when it was made again
  on.set(false)
  t.run_for(@ui.move_most_ms)
  assert_eq(seen(), -1.0)
  on.set(true)
  t.draw()
  assert_eq(seen(), 1.0)
  t.run_for(@ui.move_most_ms)
  // while its words fly here
  flying.set(true)
  t.draw()
  assert_eq(seen(), 0.0)
  flying.set(false)
  t.draw()
  assert_eq(seen(), 1.0)
  // sent again at another moment (now): unseen again till it has been on its way as long
  since.set(t.time())
  t.draw()
  assert_eq(seen(), 0.0)
  t.run_for(sending_shows_ms)
  assert_eq(seen(), 1.0)
  assert_eq(t.audit(), [])
}

///|
test "a ring filling as what it waits on comes: none known, the spinner's quarter turning; known, the accent from its top as far round, told anew drawn there over progress_ms" {
  let coming : @signals.Signal[Double?] = @signals.signal(None)
  let t = small_rows_new(390.0, fn(v, _) { @sf.progress_spinner_node(v, fn() { coming.get() }) |> ignore })
  let arc = fn() {
    let accent = @sf.theme().p.accent
    t.drawn_lines().filter(fn(l) { l.5 == accent }).length()
  }
  t.run_for(@ui.move_most_ms)
  assert_true(arc() > 0)
  // known: there at once
  coming.set(Some(0.25))
  t.draw()
  let a = arc()
  assert_true(a > 0)
  // told anew: on its way there, then as far round as three quarters
  coming.set(Some(0.75))
  t.run_for(@kit.progress_ms / 2.0)
  let mid = arc()
  t.run_for(@kit.progress_ms)
  let end = arc()
  assert_true(a < mid && mid < end, msg="\{a} \{mid} \{end}")
  assert_eq(t.audit(), [])
}

///|
test "a row's room: its body in from the pane's sides, the room over it as said, its node and key given back and told to what lays things over it" {
  let told : Array[String] = []
  let made : Ref[MessageRowNode?] = Ref(None)
  let top = @signals.signal(list_gap)
  let t = small_rows_new(760.0, fn(v, _) {
    made.val = Some(
      message_row_frame_node(
        v,
        "line",
        fn() { row_side(760.0) },
        fn() { top.get() },
        fn(m) { unread_line_node(m) |> ignore },
        over=fn(_, key) { told.push(key) },
      ),
    )
  })
  t.run_for(@ui.move_most_ms)
  assert_eq(told, ["line"])
  assert_true(made.val is Some({ key: "line", .. }))
  let side = row_side(760.0)
  let rules = t.drawn_rects().filter(fn(r) { r.3 <= 1.0 && r.2 > 0.0 })
  assert_eq(rules.length(), 2)
  assert_true((rules[0].0 - side).abs() <= 0.5)
  assert_true((rules[1].0 + rules[1].2 - (760.0 - side)).abs() <= 0.5)
  let said = @sf.t("web-main.chat.unreadLine")
  let (_, y, _, _) = t.rect_of(said).unwrap()
  assert_true(y >= list_gap)
  // the room over it as it is said anew (joined to the one before)
  top.set(joined_gap)
  t.run_for(@ui.move_most_ms)
  let (_, y2, _, _) = t.rect_of(said).unwrap()
  assert_true((y - y2 - (list_gap - joined_gap)).abs() <= 0.5, msg="\{y} \{y2}")
  assert_eq(t.audit(), [])
}

///|
test "where the chat stands, watching: its icon beating in its column, the words after it" {
  let t = small_rows_new(390.0, fn(v, _) {
    // (a spinner beside it, till lead_icon_node's watching alone passes the Tester's frame check: a frame of its looks
    // alone asks for the next at once, built whole it asks at the resident clock's next step; reported to the
    // coordinator of the migration, 2026-11-11, being mended apart; take it out with that mend)
    @sf.spinner_node(v) |> ignore
    chat_state_line_node(v, fn() { "在看 CI" }, fn() { "watch" }, fn() { "在看 CI" }) |> ignore
  })
  t.run_for(@ui.move_most_ms)
  let (x, _, _, _) = t.rect_of("在看 CI").unwrap()
  let shapes = t.drawn_shapes()
  assert_true(shapes.length() > 0)
  let icon_end = shapes.fold(init=0.0, fn(a, s) { if s.0 + s.2 > a { s.0 + s.2 } else { a } })
  assert_true(x >= icon_end - 2.0 * state_icon_out, msg="\{x} \{icon_end}")
  assert_eq(t.audit(), [])
}
