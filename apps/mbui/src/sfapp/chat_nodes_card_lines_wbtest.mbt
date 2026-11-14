// An agent's card over its name in a chat's page made as nodes (sfbase's chat_page_nodes), on a wide page: its latest
// lines run on as they change while it shows, from the frame they change, in one motion (the chat's principle that only
// what happens while it is watched moves, and once): those that stay go up a line together, the first going up and
// out as it fades, the new coming under them; nothing of the card or round it moves for it. A card opened with its lines
// there, or opened after they changed, shows them at once.

///|
/// The fixture's chat with an agent's card (chat-agent-card) opened on a chat's page made as nodes, 1280 by 800, its
/// card's latest lines as `latest` says; where the pointer rests to open its last agent's card (on its name).
fn card_lines_page(latest : @signals.Signal[(Array[(String, String)], Int)]) -> (@ui.Tester, Double, Double) raise {
  new_run()
  @sf.presenters_reset()
  @sfbase.chat_page_nodes.set(true)
  let base = fixture("chat-agent-card")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "agentCard" {
        let (lines, v) = latest.get()
        {
          value: Some({
            "latest": Json::array(
              lines.map(fn(l) { Json::object({ "key": Json::string(l.0), "text": Json::string(l.1) }) }),
            ),
            "attention": [],
          }),
          error: None,
          version: v,
        }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  // (the last agent's name drawn: its card's trigger)
  let last = t
    .words()
    .filter(fn(w) { w.0 == "Claude" && w.5 > 0.0 })
    .iter()
    .fold(init=None, fn(acc : (String, Double, Double, Double, Double, Double)?, w) {
      match acc {
        Some(a) if a.2 >= w.2 => acc
        _ => Some(w)
      }
    })
  guard last is Some(name) else { fail("no agent's message") }
  (t, name.1 + name.3 / 2.0, name.2 + name.4 / 2.0)
}

///|
/// Where words `s` are drawn now, seen (their top and how faint), each place they are.
fn card_line_at(t : @ui.Tester, s : String) -> Array[(Double, Double)] {
  t.words().filter(fn(w) { w.0 == s && w.5 > 0.0 }).map(fn(w) { (w.2, w.5) })
}

///|
/// Every other word drawn and seen now, but those of `lines`, by what it says: where it is.
fn card_round(t : @ui.Tester, lines : Array[String]) -> Map[String, (Double, Double)] {
  let out : Map[String, (Double, Double)] = Map([])
  for w in t.words() {
    if w.5 > 0.0 && !lines.contains(w.0) {
      out[w.0] = (w.1, w.2)
    }
  }
  out
}

///|
// kept across runs: a value (no field of it changes)
let card_lines_three : Array[(String, String)] = [
  ("k1", "读了 src/ui/list.mbt"),
  ("k2", "跑了列表的测试"),
  ("k3", "改了 src/ui/list.mbt"),
]

///|
// kept across runs: a value (no field of it changes)
let card_lines_next : Array[(String, String)] = [
  ("k2", "跑了列表的测试"),
  ("k3", "改了 src/ui/list.mbt"),
  ("k4", "提交了改动"),
]

///|
test "a chat's page made as nodes, wide: an agent's card's latest lines run on as they change while it shows, in one motion from the frame they change, the first going up and out, the new coming under them, nothing round them moving" {
  let latest : @signals.Signal[(Array[(String, String)], Int)] = @signals.signal((card_lines_three, 1))
  let (t, x, y) = card_lines_page(latest)
  t.move_to(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0 + @ui.move_most_ms)
  let near = fn(a : Double, b : Double) { (a - b).abs() < 0.01 }
  let one = fn(s : String) -> (Double, Double)? {
    match card_line_at(t, s) {
      [p] => Some(p)
      _ => None
    }
  }
  guard (one("读了 src/ui/list.mbt"), one("跑了列表的测试"), one("改了 src/ui/list.mbt")) is (Some(p1), Some(p2), Some(p3)) else {
    fail("the card's three lines not drawn once each, at rest")
  }
  let (y1, y2, y3) = (p1.0, p2.0, p3.0)
  let pitch = y2 - y1
  assert_true(pitch > 10.0 && near(y3 - y2, pitch), msg="at rest: \{Repr((y1, y2, y3))}")
  let words = ["读了 src/ui/list.mbt", "跑了列表的测试", "改了 src/ui/list.mbt", "提交了改动"]
  let round = card_round(t, words)
  // (on each frame drawn from the change on: those that stay a line apart, going up, never back; the new one, where
  // drawn, a line under the last; the gone one's copy a line over the first; nothing else moved)
  let faults : Array[String] = []
  let last_y = Ref(y2)
  t.each_frame(
    Some(fn() {
      let now = t.time()
      match (one("跑了列表的测试"), one("改了 src/ui/list.mbt")) {
        (Some(a), Some(b)) => {
          if !near(b.0 - a.0, pitch) || a.0 > last_y.val + 0.01 || a.0 < y1 - 0.01 || a.0 > y2 + 0.01 {
            faults.push("\{now}: those staying at \{a.0}, \{b.0}")
          }
          last_y.val = a.0
          match one("提交了改动") {
            Some(c) if !near(c.0 - a.0, pitch * 2.0) => faults.push("\{now}: the new one at \{c.0}")
            _ => ()
          }
          match one("读了 src/ui/list.mbt") {
            Some(g) if !near(a.0 - g.0, pitch) => faults.push("\{now}: the gone one at \{g.0}")
            _ => ()
          }
        }
        _ => faults.push("\{now}: those staying not drawn once each")
      }
      for k, p in card_round(t, words) {
        match round.get(k) {
          Some(q) if q != p => faults.push("\{now}: 「\{k}」 moved from \{Repr(q)} to \{Repr(p)}")
          _ => ()
        }
      }
    }),
  )
  // one more done: the first goes, the next comes
  latest.set((card_lines_next, 2))
  t.frame()
  // the first frame drawn after it (a frame on from its moment, their way set out then): those that stay on their way
  // up from where they were, short of a line; the new one, faint yet, a line under them; the gone one's copy a line over
  // them, still more seen than not
  guard (one("跑了列表的测试"), one("改了 src/ui/list.mbt")) is (Some(a), Some(b)) else {
    fail("as they change: those staying not drawn")
  }
  assert_true(
    a.0 <= y2 + 0.01 && a.0 > y1 + pitch / 2.0 && near(b.0 - a.0, pitch),
    msg="as they change: \{Repr((a, b))}, at rest \{Repr((y1, y2, y3))}",
  )
  match one("提交了改动") {
    Some(c) => assert_true(c.1 < 0.5 && near(c.0 - b.0, pitch), msg="the new one as they change: \{Repr(c)}")
    None => ()
  }
  guard one("读了 src/ui/list.mbt") is Some(g) else { fail("the gone one not drawn as they change") }
  assert_true(near(a.0 - g.0, pitch) && g.1 > 0.5, msg="the gone one as they change: \{Repr(g)}")
  // half way: on their way up together
  t.run_for(@sfpages.lines_ms / 2.0)
  guard one("跑了列表的测试") is Some(m) else { fail("half way: not drawn") }
  assert_true(m.0 < y2 - 1.0 && m.0 > y1 + 1.0, msg="half way: \{m.0}")
  // there: a line up each, the new one whole a line under them, the copy gone
  t.run_for(@sfpages.lines_ms / 2.0 + @ui.move_most_ms)
  t.each_frame(None)
  guard (one("跑了列表的测试"), one("改了 src/ui/list.mbt"), one("提交了改动")) is (Some(e1), Some(e2), Some(e3)) else {
    fail("at rest: the three not drawn once each")
  }
  assert_true(near(e1.0, y1) && near(e2.0, y2) && near(e3.0, y3), msg="at rest: \{Repr((e1, e2, e3))}")
  assert_true(e1.1 > 0.99 && e2.1 > 0.99 && e3.1 > 0.99, msg="at rest, faint: \{Repr((e1, e2, e3))}")
  assert_eq(card_line_at(t, "读了 src/ui/list.mbt").length(), 0, msg="the gone one's copy at rest")
  assert_true(faults.is_empty(), msg=faults.iter().take(6).collect().join("\n"))
  for k, p in card_round(t, words) {
    match round.get(k) {
      Some(q) => assert_eq(q, p, msg="「\{k}」 at rest")
      None => ()
    }
  }
}

///|
test "a chat's page made as nodes, wide: an agent's card opened with its lines there shows them at once, a line apart from its first frame; opened after they changed, the new ones, nothing running on" {
  for changed in [false, true] {
    let latest : @signals.Signal[(Array[(String, String)], Int)] = @signals.signal((card_lines_three, 1))
    let (t, x, y) = card_lines_page(latest)
    if changed {
      // (changed while no card shows)
      latest.set((card_lines_next, 2))
      t.run_for(@ui.move_most_ms)
    }
    let lines = if changed { card_lines_next } else { card_lines_three }
    let gone = if changed { "读了 src/ui/list.mbt" } else { "提交了改动" }
    let faults : Array[String] = []
    t.each_frame(
      Some(fn() {
        let ps = lines.map(fn(l) { card_line_at(t, l.1) })
        guard ps.iter().all(fn(p) { p.length() == 1 }) else { return }
        let (a, b, c) = (ps[0][0], ps[1][0], ps[2][0])
        // (as they are each frame they are seen: evenly a line apart, at whatever scale the card comes at, as faint as
        // each other)
        if (c.0 - b.0 - (b.0 - a.0)).abs() > 0.5 {
          faults.push("\{t.time()}: at \{a.0}, \{b.0}, \{c.0}")
        }
        if (a.1 - b.1).abs() > 0.01 || (b.1 - c.1).abs() > 0.01 {
          faults.push("\{t.time()}: faint apart \{a.1}, \{b.1}, \{c.1}")
        }
        if card_line_at(t, gone).length() > 0 {
          faults.push("\{t.time()}: 「\{gone}」 drawn")
        }
      }),
    )
    t.move_to(x, y)
    t.run_for(@sfpages.hover_open_ms * 2.0 + @ui.move_most_ms)
    t.each_frame(None)
    let ps = lines.map(fn(l) { card_line_at(t, l.1) })
    assert_true(ps.iter().all(fn(p) { p.length() == 1 && p[0].1 > 0.99 }), msg="changed \{changed}: \{Repr(ps)}")
    let pitch = ps[1][0].0 - ps[0][0].0
    assert_true(pitch > 10.0 && (ps[2][0].0 - ps[1][0].0 - pitch).abs() < 0.01, msg="changed \{changed}: \{Repr(ps)}")
    assert_eq(card_line_at(t, gone).length(), 0, msg="changed \{changed}")
    assert_true(faults.is_empty(), msg="changed \{changed}: " + faults.iter().take(6).collect().join("\n"))
  }
}
