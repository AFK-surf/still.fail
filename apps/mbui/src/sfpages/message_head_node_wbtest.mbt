// A message's head as nodes (message_head_node.mbt) and the row it makes whole, what was said elsewhere
// (message_others_node.mbt sent_elsewhere_node), set beside the old view's (message.mbt sent_elsewhere) on the same
// fixture: the same words where they were, the same rectangles drawn, in each state (sent, failed, given from there, a
// Feishu chat's, still.fail's own chat's), under the pointer, its time pressed.

///|
/// What a row stands in, in both: a column over the window, a little under its top.
// kept across runs: a value (no field of it changes)
let head_frame : @ui.Style = @ui.css("w=Full pt=S4")

///|
/// One of the fixture's elsewhere messages: `failed`, `received`, its place's `surface` and link, by an agent of the
/// chat (s-c1) or with no maker.
fn head_said(
  failed? : Bool = false,
  received? : Bool = false,
  surface? : String = "slack:T1",
  url? : String = "https://acme.slack.com/archives/C1/p1",
  maker? : Bool = true,
) -> Elsewhere {
  let by : Json = if received {
    @sffixture.by_person("Ana")
  } else if maker {
    @sffixture.by_agent("anthropic", "claude", "s-c1")
  } else {
    { "name": "still.fail" }
  }
  @sfbase.elsewhere_of({
    "key": "e9",
    "text": "安装包签名已经核对完了",
    "place": { "name": "星火#发布", "surface": Json::string(surface), "url": Json::string(url) },
    "failed": failed,
    "received": received,
    "by": by,
    "time": @sffixture.ago("3 分钟前", "2026-11-11 21:04"),
  })
}

///|
/// The fixture's chat's view: its agent s-c1.
fn head_view() -> ChatView {
  @sfbase.chat_view_made({ "title": "发布", "messages": [], "agents": [{ "session": { "key": "s-c1" } }] })
}

///|
/// `e` drawn by the old view, `w` wide, inline where `inline`.
fn head_old(e : Elsewhere, w : Double, inline : Bool, platform? : Int = 0) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let src = @sffixture.fixture("history")
  let view = head_view()
  let here : MessageHere = { station: "ws1/st1", session: "s1", view, go: None, inline, gutter: 0.0, list: None, core: None }
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { c.box(style=head_frame, fn() { row_box(c, row_side(w), 0.0, fn() { sent_elsewhere(c, src, here, e) }) |> ignore }) |> ignore })
    },
    w~,
    h=240.0,
    platform~,
  )
}

///|
/// `e` drawn by the nodes, `w` wide (its list as wide: inline where narrow; `width_now`, its list's width as it says).
fn head_new(
  e : Elsewhere,
  w : Double,
  platform? : Int = 0,
  made? : Ref[MessageRowNode?] = Ref(None),
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
  width_now? : @signals.Signal[Double],
) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let src = @sffixture.fixture("history")
  let view = head_view()
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let tips = @sf.TipLayer::new(fn() { Some(root) })
      let here : MessageNodeHere = {
        station: "ws1/st1",
        session: "s1",
        view: fn() { view },
        width: match width_now {
          Some(s) => fn() { s.get() }
          None => fn() { w }
        },
        tips,
        stint: fn() { 0 },
        jump: None,
      }
      root.box(fn(f) {
        @sf.style_node(f, fn() { head_frame })
        made.val = Some(sent_elsewhere_node(f, src, here, "s:" + e.key, fn() { row_side((here.width)()) }, fn() { 0.0 }, fn() { e }, over~))
      })
      |> ignore
    },
    w~,
    h=240.0,
    platform~,
  )
}

///|
/// The fixture's states, by name.
fn head_cases() -> Array[(String, Elsewhere)] {
  [
    ("sent", head_said()),
    ("failed", head_said(failed=true)),
    ("received", head_said(received=true)),
    ("feishu", head_said(surface="feishu", url="")),
    ("own", head_said(surface="chat", url="", maker=false)),
  ]
}

///|
/// What a Tester draws: its words (where, how big, how opaque) and its rectangles, a line each.
/// What is drawn under `from` (its top) is said `up` higher: an inline head's line of where it went, gone further down
/// than the old view's (route_line_down), set where the old one drew it.
fn head_drawn(t : @ui.Tester, from? : Double = 1.0e9, up? : Double = 0.0) -> String {
  let y = fn(at : Double) { if at >= from { at - up } else { at } }
  t.words().map(fn(w) { "\{w.0}@\{w.1},\{y(w.2)} \{w.3}x\{w.4} a\{w.5}" }).join("\n") +
  "\n" +
  t.drawn_rects().map(fn(r) { "\{r.0},\{y(r.1)} \{r.2}x\{r.3} \{r.4}" }).join("\n")
}

///|
/// What `old` (made by head_old, drawn at its moment) draws, said before another Tester is made (a Tester's draw list
/// is the last made one's), and how far down its time ends where `inline` (what is under it the new one draws
/// route_line_down further down).
fn head_old_drawn(old : @ui.Tester, inline : Bool) -> (String, Double) {
  let (_, ty, _, th) = old.rect_of("3 分钟前").unwrap()
  (head_drawn(old), if inline { ty + th + 1.0 } else { 1.0e9 })
}

///|
test "what was said elsewhere, made once as nodes, is drawn as the old view drew it: each state, wide and narrow, its time pressed, its words at 1.3" {
  for c in head_cases() {
    for width in [(760.0, false), (390.0, true)] {
      let at = "\{c.0} at \{width.0}"
      let old = head_old(c.1, width.0, width.1)
      old.run_for(@ui.move_most_ms)
      let (was, from) = head_old_drawn(old, width.1)
      let t = head_new(c.1, width.0)
      t.run_for(@ui.move_most_ms)
      assert_eq(head_drawn(t, from~, up=route_line_down()), was, msg=at)
      let faults = t.audit()
      assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
    }
  }
  // its time pressed: when it was, in both
  let old = head_old(head_said(), 760.0, false)
  old.run_for(@ui.move_most_ms)
  old.tap_text("3 分钟前")
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  absolute_times.set(false)
  let t = head_new(head_said(), 760.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("3 分钟前")
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t), was)
  // the words at 1.3, narrow
  let old = head_old(head_said(), 390.0, true)
  old.set_font_scale(1.3)
  old.run_for(@ui.move_most_ms)
  let (was, from) = head_old_drawn(old, true)
  let t = head_new(head_said(), 390.0)
  t.set_font_scale(1.3)
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t, from~, up=route_line_down()), was)
  let faults = t.audit()
  absolute_times.set(false)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "its head: the picture out in the margin before the name, where it went and its time after it; inline, the route on a line of its own" {
  let t = head_new(head_said(failed=true), 760.0)
  t.run_for(@ui.move_most_ms)
  let (nx, ny, _, _) = t.rect_of("Claude").unwrap()
  let (rx, ry, _, _) = t.rect_of("发送到").unwrap()
  let (px, py, _, _) = t.rect_of("星火#发布").unwrap()
  let (fx, fy, _, _) = t.rect_of("发送失败").unwrap()
  let (tx, ty, _, _) = t.rect_of("3 分钟前").unwrap()
  let (_, wy, _, _) = t.rect_of("安装包签名已经核对完了").unwrap()
  assert_true(nx < rx && rx < px && px < fx && fx < tx, msg="\{Repr((nx, rx, px, fx, tx))}")
  assert_true((ry - ny).abs() < 4.0 && (py - ny).abs() < 4.0 && (ty - ny).abs() < 4.0 && (fy - ny).abs() < 4.0)
  assert_true(wy > ny)
  // (its picture, the agent's ground, before the name in the margin)
  let ground = t.drawn_rects().filter(fn(r) { r.2 == 18.0 && r.3 == 18.0 })
  assert_true(ground.length() == 1 && ground[0].0 + ground[0].2 <= nx, msg="\{Repr(ground)}")
  let faults = t.audit()
  assert_true(faults.is_empty(), msg=faults.join(" | "))
  // inline: where it went under the name and time, over its words
  let t = head_new(head_said(), 390.0)
  t.run_for(@ui.move_most_ms)
  let (nx, ny, _, _) = t.rect_of("Claude").unwrap()
  let (_, ry, _, _) = t.rect_of("发送到").unwrap()
  let (_, wy, _, _) = t.rect_of("安装包签名已经核对完了").unwrap()
  assert_true(ny < ry && ry < wy, msg="\{Repr((ny, ry, wy))}")
  let ground = t.drawn_rects().filter(fn(r) { r.2 == 18.0 && r.3 == 18.0 })
  assert_true(ground.length() == 1 && ground[0].0 + ground[0].2 <= nx, msg="\{Repr(ground)}")
  let faults = t.audit()
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "as the list's width turns it inline or back, the frame it turns in draws it as one made so draws it, nothing on its way" {
  for to in [true, false] {
    let e = head_said()
    let (from_w, to_w) = if to { (760.0, 390.0) } else { (390.0, 760.0) }
    let now = @signals.signal(from_w)
    let t = head_new(e, from_w, width_now=now)
    t.run_for(@ui.move_most_ms)
    // (the window and its list narrowed or widened at once: drawn so in one frame)
    now.set(to_w)
    t.resize(to_w, 240.0)
    let turned = head_drawn(t)
    let faults = t.audit()
    assert_true(faults.is_empty(), msg="\{to}: " + faults.join(" | "))
    let made = head_new(e, to_w)
    made.run_for(@ui.move_most_ms)
    assert_eq(turned, head_drawn(made), msg="inline \{to}")
  }
}

///|
test "inline, the time and the place on the line under it each have a press's room, a keyboard and mouse's and a finger's" {
  for platform in [0, 2] {
    let t = head_new(head_said(), 390.0, platform~)
    t.run_for(@ui.move_most_ms)
    // (the time's room whole: nothing said of it)
    let faults = t.audit().filter(fn(f) { f.contains("3 分钟前") })
    assert_true(faults.is_empty(), msg="platform \{platform}: " + faults.join(" | "))
    let faults = t.audit()
    assert_true(faults.is_empty(), msg="platform \{platform}: " + faults.join(" | "))
  }
}

///|
test "its time pressed says when it was, every time the other way, and again how long ago; under the pointer, its tip says the other" {
  let t = head_new(head_said(), 760.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("3 分钟前") is Some(_) && t.find("2026-11-11 21:04") is None)
  let (x, y) = t.find("3 分钟前").unwrap()
  t.move_to(x + 2.0, y + 2.0)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
  // (its tip under it)
  let (_, ty) = t.find("2026-11-11 21:04").unwrap()
  assert_true(ty > y, msg="\{Repr((y, ty))}")
  t.tap_text("3 分钟前")
  t.run_for(@ui.move_most_ms)
  assert_true(absolute_times.get())
  assert_true(t.find("3 分钟前") is None || t.rect_of("2026-11-11 21:04").unwrap().1 < y + 4.0)
  t.tap_text("2026-11-11 21:04")
  t.run_for(@ui.move_most_ms)
  assert_true(!absolute_times.get())
  assert_true(t.rect_of("3 分钟前").unwrap().1 < y + 4.0)
  let faults = t.audit()
  absolute_times.set(false)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
/// The ground drawn under point (`x`, `y`) of a Tester's, the innermost there (its colour; 0 none).
fn head_ground_at(t : @ui.Tester, x : Double, y : Double) -> Int64 {
  let under = t.drawn_rects().filter(fn(r) { x >= r.0 && x <= r.0 + r.2 && y >= r.1 && y <= r.1 + r.3 && r.4 != 0L })
  match under.iter().fold(init=None, fn(a : (Double, Double, Double, Double, Int64)?, r) {
    match a {
      Some(b) if b.2 * b.3 <= r.2 * r.3 => a
      _ => Some(r)
    }
  }) {
    Some(r) => r.4
    None => 0L
  }
}

///|
test "the place pressed opens it where it has its link, its ground lit under the pointer; without one, neither" {
  for url in ["https://acme.slack.com/archives/C1/p1", ""] {
    let t = head_new(head_said(url~), 760.0)
    t.run_for(@ui.move_most_ms)
    let (x, y) = t.find("星火#发布").unwrap()
    let rest = head_ground_at(t, x + 2.0, y + 2.0)
    assert_true(rest != 0L)
    t.move_to(x + 2.0, y + 2.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(head_ground_at(t, x + 2.0, y + 2.0) != rest, url != "", msg=url)
    t.tap_text("星火#发布")
    t.draw()
    assert_eq(t.opened(), if url != "" { [url] } else { [] }, msg=url)
    let faults = t.audit()
    assert_true(faults.is_empty(), msg=url + ": " + faults.join(" | "))
  }
}

///|
test "the row is found by its key: made in its row's room, what is laid over it told its node and key once" {
  let made : Ref[MessageRowNode?] = Ref(None)
  let told : Array[String] = []
  let t = head_new(head_said(), 760.0, made~, over=fn(_, key) { told.push(key) })
  t.run_for(@ui.move_most_ms)
  guard made.val is Some(row) else { fail("no row") }
  assert_eq(row.key, "s:e9")
  assert_eq(told, ["s:e9"])
  assert_true(row.node.alive())
  let faults = t.audit()
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}


