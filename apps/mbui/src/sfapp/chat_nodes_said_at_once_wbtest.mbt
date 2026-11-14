// A chat's page made with its inside nodes (sfbase's chat_page_nodes on), what a press causes on the screen in the
// press's own frame, not when the core answers a round trip later, and the core's later word changing nothing seen (the
// owner's, written in the old page: sent.mbt's head and sent_joins; chat_list.mbt's sent_here_view, 2026-11-10
// 「现在发一条消息都会有奇怪的跳动」; its answered_at, 2026-11-09 「点选项时「处理中」立刻出来」; row_keys, the row keeping
// one identity from the press on). On 小屏 and 大屏, the core answering what is pressed late by each of sao_lates, at
// the list's end. Words sent, with no card waiting or under a decision card waiting: in the press's frame the list holds
// the viewer's row and, under the card, the card answered and its agent's working line; as the core's word comes, and
// till its station has what was sent, the list is as it is in the same run where the core never answers, its keys,
// each row's top and height, each row the same node; with no card, from the press to rest no row over the newest goes
// down (under a card that is the list's way's to hold, mbui's View::scrolls_window). An option picked on the card goes to the
// core and its answer's row comes as the core has it (the old page's design): the card answered, that row and the
// agent's working line in one change at the core's word, nothing seen changing as the station has it.

///|
/// How late the core answers what is pressed, in ms.
let sao_lates : Array[Double] = [0.0, 16.0, 120.0, 400.0, 700.0]

///|
/// The screens: name, width, height, platform.
let sao_screens : Array[(String, Double, Double, Int)] = [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)]

///|
/// The option picked on the card (chat-ask-end's).
let sao_option : String = "一起改"

///|
/// What is pressed: words sent with no card waiting, words sent under the card waiting, an option picked on it.
priv enum SaoCase {
  Words
  UnderCard
  Pick
}

///|
/// A frame of the chat's list as a test reads it: when, how many keys it has, its rows drawn (where each is among its
/// keys, its node, its top, its height), whether the viewer's words are drawn in one of them, whether the card waiting
/// is answered, whether an agent's working line shows.
priv struct SaoLook {
  at : Double
  count : Int
  rows : Array[(Int, @view.NodeId, Double, Double)]
  own : Bool
  answered : Bool
  line : Bool
}

///|
/// The chat's list of the window's tree now: the one drawn furthest right (大屏's sidebar holds a list of its own).
fn sao_list() -> @view.ListSeen? {
  let mut best : @view.ListSeen? = None
  let mut best_x = @double.neg_infinity
  for l in @ui.view_tree().unwrap().lists_seen() {
    guard l.rows is [first, ..] else { continue }
    let (_, _, (x, _, _, _)) = first
    if x >= best_x {
      best_x = x
      best = Some(l)
    }
  }
  best
}

///|
/// What `t` draws of the chat's list now (SaoLook), the card answered as `answered` words say it (None: no card).
fn sao_look(t : @ui.Tester, answered : String?) -> SaoLook {
  let list = sao_list()
  let rows = match list {
    Some(l) => l.rows.map(fn(r) { (r.0, r.1, (r.2).1, (r.2).3) })
    None => []
  }
  // (the viewer's words drawn: in their row, or flying into it as its key comes)
  let own = t.find(cr_sent) is Some(_) || t.run_rects(cr_sent).length() > 0
  {
    at: t.time(),
    count: list.map(fn(l) { l.count }).unwrap_or(0),
    rows,
    own,
    answered: match answered {
      Some(a) => t.find(a) is Some(_) || t.run_rects(a).length() > 0
      None => false
    },
    line: t.find(tr("android-chat.chat.working")) is Some(_),
  }
}

///|
/// How long a case is looked at from the press: past the station having what was sent once the core has it at the
/// latest, and the list's way after that.
let sao_until_ms : Double = 700.0 + @sffixture.fix_deliver_ms + @ui.move_most_ms

///|
/// The fixture's chat s-c1 with its page's inside nodes on `screen`, at rest at its end, then pressed as `case` says, the
/// core answering what was pressed `late` ms after (None: never): each frame from the press's own on for sao_until_ms,
/// when the press was and the frame before it. `on_pixels`: its list's rows set on the host's pixels, as every
/// device's host sets them (Tester::set_rows_on_pixels).
fn sao_run(
  screen : (String, Double, Double, Int),
  case : SaoCase,
  late : Double?,
  on_pixels? : Bool = false,
) -> (Array[SaoLook], Double, SaoLook) raise {
  let (_, w, h, platform) = screen
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let base = fixture(if case is Words { "chat" } else { "chat-ask-end" })
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name != "chat.send" && name != "decision.answer" {
        (base.call)(name, params, done)
        return
      }
      match late {
        Some(ms) => @sffixture.fix_later(ms, fn() { (base.call)(name, params, done) })
        None => ()
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.set_rows_on_pixels(on_pixels)
  t.run_for(@ui.move_most_ms)
  let answered = match case {
    Words => None
    UnderCard => Some("你 回复了")
    Pick => Some("你 选择了「" + sao_option + "」")
  }
  if !(case is Pick) {
    guard composer_field(t) is Some((fx, fy, fw, fh)) else { fail("no composer's field") }
    t.tap(fx + fw / 2.0, fy + fh / 2.0)
    t.type_text(cr_sent)
    t.run_for(@ui.move_most_ms)
  }
  let before = sao_look(t, answered)
  let press = t.time()
  match case {
    Pick => t.tap_text(sao_option)
    _ => tap_send(t)
  }
  let looks = [sao_look(t, answered)]
  while t.time() < press + sao_until_ms {
    t.frame()
    looks.push(sao_look(t, answered))
  }
  (looks, press, before)
}

///|
/// A frame's keys and rows in short: how many keys, each row drawn where it is among them, its top and height.
fn sao_shape(x : SaoLook) -> String {
  let r = fn(v : Double) { (v * 100.0).round() / 100.0 }
  "\{x.count} keys: " + x.rows.map(fn(q) { "\{q.0}@\{r(q.2)}+\{r(q.3)}" }).join(" ")
}

///|
/// What breaks the principle in `looks` (sao_run's, the core `late` ms late) against `never`'s (the same, the core never
/// answering), `case` pressed at `press`: each said once.
fn sao_faults(
  case : SaoCase,
  late : Double,
  looks : Array[SaoLook],
  never : Array[SaoLook],
  press : Double,
  before : SaoLook,
) -> Array[String] {
  let out : Array[String] = []
  match case {
    Pick => sao_pick_faults(late, looks, press, before, out)
    _ => {
      // (a) in the press's own frame: a key more for each row that comes
      let first = looks[0]
      let more = if case is UnderCard { 2 } else { 1 }
      if first.count < before.count + more {
        out.push("(a) \{first.count - before.count} keys more in the press's frame, \{more} to come")
      }
      if !first.own {
        out.push("(a) the viewer's words not drawn in the press's frame")
      }
      if !(case is Words) && !first.answered {
        out.push("(a) the card not answered in the press's frame")
      }
      if !(case is Words) && !first.line {
        out.push("(a) the answered agent's working line not in the list in the press's frame")
      }
      // (b) as the core's word comes, till its station has what was sent: as where it never answers, each row the same node
      let core_at = press + late
      let till = core_at + @sffixture.fix_deliver_ms
      let mut told = false
      for i, l in looks {
        guard l.at < till && !told else { continue }
        guard never.get(i) is Some(n) && n.at == l.at else {
          out.push("(b) the frames apart from the run the core never answers at +\{l.at - press} ms")
          told = true
          continue
        }
        if sao_shape(l) != sao_shape(n) {
          out.push("(b) at +\{l.at - press} ms: \{sao_shape(l)}; where it never answers \{sao_shape(n)}")
          told = true
        }
      }
      // (the row the same node across the core's word, and across the station having what was sent where nothing new
      // comes with it: what was sent under the card, its agent at work already)
      let across = fn(at : Double, what : String) {
        guard looks.search_by(fn(l) { l.at >= at }) is Some(i) && i > 0 else { return }
        let (a, b) = (looks[i - 1], looks[i])
        for r in b.rows {
          match a.rows.iter().find_first(fn(q) { q.0 == r.0 }) {
            Some(q) if q.1 != r.1 => {
              out.push("(b) row \{r.0} made anew as \{what} (+\{b.at - press} ms)")
              break
            }
            _ => ()
          }
        }
        if case is UnderCard && what == "the station has it" {
          if sao_shape(a) != sao_shape(b) {
            out.push("(b) as the station has it (+\{b.at - press} ms): \{sao_shape(b)}; the frame before \{sao_shape(a)}")
          }
        }
      }
      across(core_at, "the core's word comes")
      across(till, "the station has it")
    }
  }
  // (c) from the press to rest no row over the newest goes down
  for i in 1..<looks.length() {
    let (a, b) = (looks[i - 1], looks[i])
    let newest = b.rows.fold(init=-1, fn(m, r) { if r.0 > m { r.0 } else { m } })
    let down = b.rows.iter().find_first(fn(r) {
      r.0 < newest && a.rows.iter().any(fn(q) { q.1 == r.1 && r.2 > q.2 + 0.01 })
    })
    match down {
      Some(r) => {
        let was = a.rows.iter().find_first(fn(q) { q.1 == r.1 }).unwrap()
        // (its top round then, frame by frame)
        let round = looks[if i >= 4 { i - 4 } else { 0 }:if i + 4 < looks.length() { i + 4 } else { looks.length() }]
          .iter()
          .map(fn(l) {
            match l.rows.iter().find_first(fn(q) { q.1 == r.1 }) {
              Some(q) => "+\{l.at - press}: \{q.2}"
              None => "+\{l.at - press}: -"
            }
          })
          .collect()
        out.push("(c) row \{r.0} down from \{was.2} to \{r.2} at +\{b.at - press} ms (\{round.join(", ")})")
        break
      }
      None => ()
    }
  }
  out
}

///|
/// What breaks the principle for an option picked (sao_faults' (a) and (b) for it), in `looks` (sao_run's, the core
/// `late` ms late, pressed at `press`, `before` the frame before), said into `out`: a pick goes to the core and its
/// answer's row comes as the core has it (the old page's design), the card answered, that row and the agent's working
/// line in one change (the owner, 2026-11-09: 「点选项时「处理中」立刻出来」): the list's keys change once from the press
/// till the agent answers, at the core's word, two keys more, the card answered and the line there in that frame; and
/// nothing seen changes as long after it as the station takes to have words sent.
// (the pick said in the press's own frame, before the core has it, is a later piece of work: a local overlay for picks)
fn sao_pick_faults(late : Double, looks : Array[SaoLook], press : Double, before : SaoLook, out : Array[String]) -> Unit {
  let core_at = press + late
  let seq = [before, ..looks].filter(fn(l) { l.at < core_at + @sffixture.fix_answer_ms })
  let changes = []
  for j in 1..<seq.length() {
    if seq[j].count != seq[j - 1].count {
      changes.push(j)
    }
  }
  let said = changes
    .map(fn(j) { "+\{seq[j].at - press} ms \{seq[j - 1].count} to \{seq[j].count}" })
    .join(", ")
  guard changes is [j] else {
    out.push("(a) the keys changed \{changes.length()} times, once to come: \{said}")
    return
  }
  let (a, b) = (seq[j - 1], seq[j])
  if b.at < core_at {
    out.push("(a) the keys changed before the core's word: \{said}")
  }
  if b.count != a.count + 2 {
    out.push("(a) \{b.count - a.count} keys more at the core's word, the answer's row and the line to come")
  }
  if !b.answered {
    out.push("(a) the card not answered in the frame its answer's row comes (+\{b.at - press} ms)")
  }
  if !b.line {
    out.push("(a) the agent's working line not there in the frame the answer's row comes (+\{b.at - press} ms)")
  }
  // (b) nothing seen changes as the station has it: its rows the same, each the same node
  let at = core_at + @sffixture.fix_deliver_ms
  guard looks.search_by(fn(l) { l.at >= at }) is Some(i) && i > 0 else { return }
  let (p, q) = (looks[i - 1], looks[i])
  if sao_shape(p) != sao_shape(q) || q.rows.iter().any(fn(r) { p.rows.iter().any(fn(x) { x.0 == r.0 && x.1 != r.1 }) }) {
    out.push("(b) as the station has it (+\{q.at - press} ms): \{sao_shape(q)}; the frame before \{sao_shape(p)}")
  }
}

///|
/// Case `case` on each screen at each of sao_lates: what breaks the principle, each run's said; of (c) alone where
/// `down`, else of (a) and (b) (each its own block: (c) is the list's way, mbui's View::scrolls_window); `on_pixels`,
/// sao_run's.
fn sao_case(case : SaoCase, down~ : Bool, on_pixels? : Bool = false) -> Unit raise {
  let all : Array[String] = []
  for screen in sao_screens {
    let never = if case is Pick { [] } else { sao_run(screen, case, None, on_pixels~).0 }
    for late in sao_lates {
      let (looks, press, before) = sao_run(screen, case, Some(late), on_pixels~)
      for f in sao_faults(case, late, looks, never, press, before) {
        if f.has_prefix("(c)") == down {
          all.push("\{screen.0}, the core \{late} ms late: \{f}")
        }
      }
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏, the core late: words sent with no card waiting in the list from the press's frame, the core's word changing nothing seen" {
  sao_case(Words, down=false)
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏, the core late: words sent with no card waiting, nothing over the newest down from the press to rest" {
  sao_case(Words, down=true)
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏, the core late: words sent under a card waiting answer it and set its agent at work in the press's frame, the core's word changing nothing seen" {
  sao_case(UnderCard, down=false)
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏, the core late: an option picked on a card waiting: the card answered, the answer's row and its agent's working line in one change, at the core's word; nothing seen changing as the station has it" {
  sao_case(Pick, down=false)
}
