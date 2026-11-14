// An answer come at a chat's list's foot is read from its top (the old page's follow_newest, the chat's page made with
// its inside nodes: chat_body_node's, by ListPlace::follow_from): the list follows its foot till the answer's top is as
// far under the bar as the list keeps its first row and follow_margin more, and holds it there; its words never go over
// the bar's foot in any frame. So held, the list is off its foot: the next message moves nothing that shows, till the
// hand takes the list back to its foot; the viewer's own words sent take it there. On 小屏 and 大屏, every frame a
// device draws from the cause to rest (Tester::run_shown), its rows on the host's pixels.

///|
/// The answer's first words (long_reply's), and the paragraphs said after them.
let rp_first : String = "列表改成虚拟列表"

///|
fn rp_paras(n : Int) -> String {
  Array::makei(n, fn(i) { "第 \{i + 1} 段，接着往下讲。" }).join("\n\n")
}

///|
/// The next message, and the one after it.
let rp_next : String = "下一条：好的，接着看"

///|
let rp_after : String = "再下一条：都改完了"

///|
/// Long enough after a cause for all it sets off to be at rest.
let rp_rest_ms : Double = 2400.0

///|
/// Where the old page has an answer's words held by its top (its top follow_margin under the room under the bar), on
/// 小屏 and 大屏.
fn rp_held_at(screen : String) -> Double {
  if screen == "小屏" {
    124.0
  } else {
    139.0
  }
}

///|
/// The margin's line on `screen`: where the list holds an answer's top (the room under the bar and follow_margin under
/// it), its words a head line under it (rp_held_at). A block on its way is drawn by how much of it shows, down from its
/// top: its words nearer that top till it is whole.
fn rp_margin_line(screen : String) -> Double {
  if screen == "小屏" {
    76.0
  } else {
    81.0
  }
}

///|
let rp_screens : Array[(String, Double, Double, Int)] = [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)]

///|
/// The fixture's chat opened as nodes on `screen`, its clock `clock`, its rows on pixels; words sent, taken by the
/// station, its agent at work (its line shown) as the answer is to come.
fn rp_open(screen : (String, Double, Double, Int), clock : Ref[Double]) -> @ui.Tester raise {
  let (_, w, h, platform) = screen
  new_run()
  @sfbase.chat_page_nodes.set(true)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.set_rows_on_pixels(true)
  t.run_for(@ui.move_most_ms)
  rp_send(t, "看一下列表")
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  t.run_for(fix_answer_ms)
  t
}

///|
/// `words` typed in the composer and sent.
fn rp_send(t : @ui.Tester, words : String) -> Unit raise {
  let mut at : (Double, Double, Double, Double)? = None
  for s in t.semantics() {
    if s.role == @ui.Role::TextField && (at is None || at.unwrap().1 < s.rect.1) {
      at = Some(s.rect)
    }
  }
  guard at is Some((fx, fy, fw, fh)) else { fail("no composer's field") }
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.type_text(words)
  t.click(Button, label=@sf.t("web-main.composer.send"))
}

///|
/// Where `words` are drawn at each frame drawn while `ms` go by from `cause` (done at the clock's moment + 1, between
/// frames), none where they are not drawn.
fn rp_frames(t : @ui.Tester, clock : Ref[Double], cause : () -> Unit, words : String, ms : Double) -> Array[Double?] {
  let ys : Array[Double?] = []
  t.each_frame(Some(fn() { ys.push(t.drawn_of(words).map(fn(d) { d.1 })) }))
  fix_later(1.0, cause)
  fix_clock_set(clock, clock.val + 1.0)
  t.draw()
  t.run_shown(ms)
  t.each_frame(None)
  ys
}

///|
/// The agent's message `seq` said now, `text` (its line going as it comes where `ends`).
fn rp_said(seq : Int, text : String, ends? : Bool = false) -> Unit {
  let fc = fix_chat("s-c1")
  fc.sent.push(
    msg(seq, "agent", @sffixture.by_agent("anthropic", "claude", "s-c1"), text, "刚刚", {
      "ts": Json::string("rp\{seq}"),
      "said": true,
    }),
  )
  if ends {
    fc.working = -1.0
    fc.about = seq
  }
}

///|
/// What is wrong with an answer's words drawn at `ys` (each frame) on `screen`: over the margin's line (rp_margin_line)
/// in a frame, or never drawn; None: nothing. Their rest, the last drawn.
fn rp_never_over(screen : String, ys : Array[Double?]) -> (String?, Double) {
  let line = rp_margin_line(screen)
  let mut last = -1.0e9
  for i, y in ys {
    match y {
      Some(y) => {
        if y < line - rp_half_px {
          return (Some("frame \{i}: its words at \{y}, over the margin's line \{line}"), y)
        }
        last = y
      }
      None => ()
    }
  }
  if last == -1.0e9 {
    (Some("its words never drawn"), last)
  } else {
    (None, last)
  }
}

///|
/// Half a device pixel, in points (the Tester draws 2 pixels a point).
let rp_half_px : Double = 0.25

///|
/// Whether the answer whose first words are rp_first rests as the rule has it on `screen`: where its top would go over the
/// margin at the list's foot, its words at the margin's line within half a device pixel; else at the foot, all of it
/// in sight over the composer's field.
fn rp_rests_right(t : @ui.Tester, screen : String, rest : Double) -> Bool {
  if (rest - rp_held_at(screen)).abs() < rp_half_px {
    return true
  }
  match t.rect_of(rp_first) {
    Some((_, y, _, h)) => y + h <= rp_field_top(t) + 0.01
    None => false
  }
}

///|
/// The composer's field's top.
fn rp_field_top(t : @ui.Tester) -> Double {
  let mut at = -1.0
  for s in t.semantics() {
    if s.role == @ui.Role::TextField && s.rect.1 > at {
      at = s.rect.1
    }
  }
  at
}

///|
/// The answer `text` come on `screen`, `mode`: "work" while its agent's line shows, "ends" the line going as it comes,
/// "over" the turn over and its line gone before it: every frame from its cause to rest, and where its words rest.
fn rp_answer(
  screen : (String, Double, Double, Int),
  text : String,
  mode : String,
) -> (@ui.Tester, Ref[Double], Array[Double?]) raise {
  let clock = Ref(0.0)
  let t = rp_open(screen, clock)
  if mode == "over" {
    fix_later(1.0, fn() { fix_chat("s-c1").working = -1.0 })
    fix_clock_set(clock, clock.val + 1.0)
    t.draw()
    t.run_for(rp_rest_ms)
  }
  let ys = rp_frames(t, clock, fn() { rp_said(170, text, ends=mode == "ends") }, rp_first, rp_rest_ms)
  (t, clock, ys)
}

///|
test "chat as nodes: an answer taller than the window, its line showing, going as it comes, or the turn over: never over the margin's line, held at it, where the old page has it, on 小屏 and 大屏" {
  for screen in rp_screens {
    for mode in ["work", "ends", "over"] {
      let (_, _, ys) = rp_answer(screen, long_reply + "\n\n" + rp_paras(30), mode)
      let (wrong, rest) = rp_never_over(screen.0, ys)
      if wrong is Some(w) {
        fail("\{screen.0}, \{mode}: \{w}")
      }
      assert_true((rest - rp_held_at(screen.0)).abs() < rp_half_px, msg="\{screen.0}, \{mode}: its words rest at \{rest}")
    }
  }
  fix_clock.val = None
}

///|
test "chat as nodes: answers of 8, 11 and 14 paragraphs: never over the margin's line; held at it where it binds, at the foot where it does not" {
  for screen in rp_screens {
    for n in [8, 11, 14] {
      for mode in ["work", "ends"] {
        let (t, _, ys) = rp_answer(screen, rp_first + "\n\n" + rp_paras(n), mode)
        let (wrong, rest) = rp_never_over(screen.0, ys)
        if wrong is Some(w) {
          fail("\{screen.0}, \{n}, \{mode}: \{w}")
        }
        assert_true(rp_rests_right(t, screen.0, rest), msg="\{screen.0}, \{n}, \{mode}: its words rest at \{rest}")
      }
    }
  }
  fix_clock.val = None
}

///|
test "chat as nodes: an answer of 8 paragraphs rests at the foot, the next message followed there" {
  for screen in rp_screens {
    let (t, clock, ys) = rp_answer(screen, rp_first + "\n\n" + rp_paras(8), "work")
    let (wrong, rest) = rp_never_over(screen.0, ys)
    if wrong is Some(w) {
      fail("\{screen.0}: \{w}")
    }
    assert_true(rest > rp_held_at(screen.0) + 1.0, msg="\{screen.0}: held at \{rest}")
    let _ = rp_frames(t, clock, fn() { rp_said(171, rp_next) }, rp_first, rp_rest_ms)
    let now = t.drawn_of(rp_first).map(fn(d) { d.1 }).unwrap_or(-1.0e9)
    assert_true(now < rest - 20.0 && t.drawn_of(rp_next) is Some(_), msg="\{screen.0}: \{rest} → \{now}")
  }
  fix_clock.val = None
}

///|
/// The hand reading the list on `screen` by `d` (down the chat where more than 0).
fn rp_hand(t : @ui.Tester, screen : (String, Double, Double, Int), d : Double) -> Unit {
  let (_, w, h, platform) = screen
  if platform == 2 {
    t.drag(w / 2.0, h * 0.6, w / 2.0, h * 0.6 - d)
  } else {
    t.move_to(w * 0.6, h / 2.0)
    t.wheel(w * 0.6, h / 2.0, d)
  }
}

///|
test "chat as nodes: held by an answer's top, the next message moves nothing that shows; the hand back at the foot, the one after is followed" {
  for screen in rp_screens {
    let (t, clock, ys) = rp_answer(screen, long_reply + "\n\n" + rp_paras(30), "work")
    let (_, rest) = rp_never_over(screen.0, ys)
    let next = rp_frames(t, clock, fn() { rp_said(171, rp_next) }, rp_first, rp_rest_ms)
    for i, y in next {
      assert_true(y is Some(y) && (y - rest).abs() < 0.01, msg="\{screen.0}, frame \{i}: \{Repr(y)}, held at \{rest}")
    }
    // the hand takes it to its foot
    rp_hand(t, screen, 6000.0)
    t.run_for(rp_rest_ms)
    let foot = t.drawn_of(rp_next).map(fn(d) { d.1 }).unwrap_or(-1.0e9)
    assert_true(foot > bar_foot() && foot < rp_field_top(t), msg="\{screen.0}: the next message not in sight at the foot: \{foot}")
    // followed there: the one after comes in, what was over it gone up
    let _ = rp_frames(t, clock, fn() { rp_said(172, rp_after) }, rp_next, rp_rest_ms)
    let now = t.drawn_of(rp_next).map(fn(d) { d.1 }).unwrap_or(-1.0e9)
    assert_true(now < foot - 20.0 && t.drawn_of(rp_after) is Some(_), msg="\{screen.0}: \{foot} → \{now}")
  }
  fix_clock.val = None
}

///|
test "chat as nodes: the viewer's own words sent while an answer's top holds the list: it goes to its foot" {
  for screen in rp_screens {
    let (t, _, _) = rp_answer(screen, long_reply + "\n\n" + rp_paras(30), "work")
    let mine = "收到，我先看"
    rp_send(t, mine)
    t.run_for(rp_rest_ms)
    let y = t.drawn_of(mine).map(fn(d) { d.1 }).unwrap_or(-1.0e9)
    assert_true(y > bar_foot() && y < rp_field_top(t), msg="\{screen.0}: what was sent at \{y}")
    let top = t.drawn_of(rp_first).map(fn(d) { d.1 }).unwrap_or(-1.0e9)
    assert_true(top < bar_foot(), msg="\{screen.0}: the answer's top still in sight at \{top}")
  }
  fix_clock.val = None
}

///|
/// Where the bell (the way to what waits to be decided) is drawn: its top; none where it does not show.
fn rp_bell(t : @ui.Tester) -> Double? {
  for s in t.semantics() {
    if s.role == @ui.Role::Button && s.label == @sf.t("web-main.chat.asks.go") {
      return Some(s.rect.1)
    }
  }
  None
}

///|
/// What is wrong with the bell's places `ys` (the moment of each frame, where it is then): a step, as fast as it went
/// from the frame before, more than twice as fast as it went either side of it; or it never moved. None: nothing.
fn rp_bell_wrong(at : Array[(Double, Double)]) -> String? {
  let ys = at.map(fn(a) { a.1 })
  let d = Array::makei(at.length() - 1, fn(i) {
    let dt = at[i + 1].0 - at[i].0
    if dt > 0.0 { (ys[i + 1] - ys[i]).abs() / dt * 1000.0 / 60.0 } else { 0.0 }
  })
  let mut moved = 0.0
  for i, x in d {
    moved = moved + x
    let before = if i > 0 { d[i - 1] } else { 0.0 }
    let after = if i + 1 < d.length() { d[i + 1] } else { 0.0 }
    // (a point or less is no step: a Move's spring is at rest within it as its declared end comes, move_spring's)
    if (ys[i + 1] - ys[i]).abs() > 1.0 && x > 2.0 * (if before > after { before } else { after }) {
      return Some("frame \{i + 1}: a step of \{x}, \{before} before it, \{after} after: \{Repr(ys)}")
    }
  }
  if moved < 1.0 {
    Some("never moved: \{Repr(ys)}")
  } else {
    None
  }
}

///|
test "chat as nodes: the bell goes up over the way to the newest as that comes, on its way, no step: as an answer holds the list, and as the hand reads up" {
  for screen in rp_screens {
    for cause in ["answer", "hand"] {
      // (held by an answer's top, then the viewer's own words sent: at its foot, what waits to be decided far up out
      // of sight, the bell shown alone)
      let (t, clock, _) = rp_answer(screen, long_reply + "\n\n" + rp_paras(30), "work")
      rp_send(t, "收到，我先看")
      fix_clock_set(clock, clock.val + fix_deliver_ms)
      t.draw()
      t.run_for(rp_rest_ms)
      guard rp_bell(t) is Some(_) else { fail("\{screen.0}: no bell at the foot") }
      let ys : Array[(Double, Double)] = []
      t.each_frame(Some(fn() { ys.push((t.time(), rp_bell(t).unwrap_or(-1.0e9))) }))
      if cause == "answer" {
        fix_later(1.0, fn() { rp_said(190, long_reply + "\n\n" + rp_paras(30)) })
        fix_clock_set(clock, clock.val + 1.0)
        t.draw()
      } else {
        rp_hand(t, screen, -300.0)
      }
      t.run_shown(rp_rest_ms)
      t.each_frame(None)
      if rp_bell_wrong(ys.filter(fn(y) { y.1 > -1.0e8 })) is Some(w) {
        fail("\{screen.0}, \{cause}: \{w}")
      }
    }
  }
  fix_clock.val = None
}

///|
test "chat as nodes: the last row going at the foot is no answer come: nothing jumps to the answer over it, the list at its foot, the next answer read from its top" {
  for screen in rp_screens {
    // a tall answer held by its top, the hand taking the list to its foot (no limit stands), a message come there
    let (t, clock, _) = rp_answer(screen, long_reply + "\n\n" + rp_paras(30), "work")
    rp_hand(t, screen, 6000.0)
    t.run_for(rp_rest_ms)
    let _ = rp_frames(t, clock, fn() { rp_said(171, rp_next) }, rp_next, rp_rest_ms)
    let last = "第 30 段"
    guard t.drawn_of(last) is Some((_, y0)) else { fail("\{screen.0}: the answer's last paragraph not in sight") }
    // the message goes (taken back, by data): the newest is the answer again, come before
    let ys = rp_frames(t, clock, fn() { fix_chat("s-c1").sent.pop() |> ignore }, last, rp_rest_ms)
    for i, y in ys {
      assert_true(
        y is Some(y) && y >= y0 - 0.01 && y <= y0 + 100.0,
        msg="\{screen.0}, frame \{i}: its last paragraph at \{Repr(y)}, at \{y0} before",
      )
    }
    assert_true(t.drawn_of(rp_next) is None, msg="\{screen.0}: what went still drawn")
    // the next answer read from its top
    let ys = rp_frames(t, clock, fn() { rp_said(172, "又一个长回答\n\n" + rp_paras(30)) }, "又一个长回答", rp_rest_ms)
    let (wrong, rest) = rp_never_over(screen.0, ys)
    if wrong is Some(w) {
      fail("\{screen.0}: the next answer: \{w}")
    }
    assert_true((rest - rp_held_at(screen.0)).abs() < rp_half_px, msg="\{screen.0}: the next answer rests at \{rest}")
  }
  fix_clock.val = None
}
